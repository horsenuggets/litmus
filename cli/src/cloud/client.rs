use super::Target;
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use std::time::Duration;
use ureq::http::Response;
use ureq::{Agent, Body};

const ORIGIN: &str = "https://apis.roblox.com";
const KEY_HEADER: &str = "x-api-key";

/// For one request, the largest of which uploads the whole place
const TIMEOUT: Duration = Duration::from_secs(300);

const PERMISSIONS_HINT: &str =
    "does the key have universe-places and luau-execution-sessions Write on this experience?";

#[derive(Debug, PartialEq)]
pub enum TaskState {
    Running,

    /// With what the task's script returned
    Complete(Vec<Value>),
    Failed(String),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Uploaded {
    version_number: u64,
}

#[derive(Deserialize)]
struct Started {
    path: String,
}

#[derive(Deserialize)]
struct Task {
    state: String,
    output: Option<Output>,
    error: Option<Problem>,
}

#[derive(Deserialize)]
struct Output {
    #[serde(default)]
    results: Vec<Value>,
}

#[derive(Deserialize)]
struct Problem {
    #[serde(default)]
    code: String,
    #[serde(default)]
    message: String,
}

impl Task {
    fn progress(self) -> TaskState {
        match self.state.as_str() {
            "COMPLETE" => TaskState::Complete(self.output.map(|output| output.results).unwrap_or_default()),
            "FAILED" => TaskState::Failed(match self.error {
                Some(problem) if !problem.message.is_empty() => problem.message,
                Some(problem) if !problem.code.is_empty() => problem.code,
                _ => "Open Cloud gave no reason".to_owned(),
            }),
            "CANCELLED" => TaskState::Failed("it was cancelled".to_owned()),
            _ => TaskState::Running,
        }
    }
}

/// Roblox's Open Cloud, as far as a test run needs it
pub struct Client {
    agent: Agent,
    key: String,
    origin: String,
}

impl Client {
    pub fn new(key: String) -> Client {
        Client::at(ORIGIN, key)
    }

    fn at(origin: &str, key: String) -> Client {
        let agent = Agent::config_builder()
            // Left to `read`, since the reason a request was refused is in its body
            .http_status_as_error(false)
            .timeout_global(Some(TIMEOUT))
            .build()
            .into();

        Client {
            agent,
            key,
            origin: origin.to_owned(),
        }
    }

    /// Saves `file` as the place's newest version, without publishing it, and returns that version's number
    pub fn upload(&self, target: &Target, file: &[u8]) -> Result<u64, String> {
        let url = format!(
            "{}/universes/v1/{}/places/{}/versions?versionType=Saved",
            self.origin, target.universe, target.place
        );

        let response = self
            .agent
            .post(&url)
            .header(KEY_HEADER, &self.key)
            .header("Content-Type", "application/octet-stream")
            .send(file);

        let uploaded: Uploaded = read("upload the place", response)?;
        Ok(uploaded.version_number)
    }

    /// Starts `script` in a server of its own holding that version of the place, and returns the task to ask after
    pub fn start(&self, target: &Target, version: u64, script: &str) -> Result<String, String> {
        let url = format!(
            "{}/cloud/v2/universes/{}/places/{}/versions/{version}/luau-execution-session-tasks",
            self.origin, target.universe, target.place
        );

        let response = self
            .agent
            .post(&url)
            .header(KEY_HEADER, &self.key)
            .header("Content-Type", "application/json")
            .send(json!({ "script": script }).to_string().as_str());

        let started: Started = read("start the task", response)?;
        Ok(started.path)
    }

    pub fn progress(&self, task: &str) -> Result<TaskState, String> {
        let url = format!("{}/cloud/v2/{task}", self.origin);
        let response = self.agent.get(&url).header(KEY_HEADER, &self.key).call();

        let task: Task = read("ask after the task", response)?;
        Ok(task.progress())
    }
}

/// What Open Cloud answered, or why the request to `action` came to nothing
fn read<T: DeserializeOwned>(action: &str, response: Result<Response<Body>, ureq::Error>) -> Result<T, String> {
    let mut response = response.map_err(|error| format!("couldn't {action}: {error}"))?;
    let status = response.status();

    let body = response
        .body_mut()
        .read_to_string()
        .map_err(|error| format!("couldn't {action}: {error}"))?;

    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err(format!("couldn't {action}: Open Cloud answered {status}; {PERMISSIONS_HINT}"));
    }

    if !status.is_success() {
        return Err(format!("couldn't {action}: Open Cloud answered {status}: {}", body.trim()));
    }

    serde_json::from_str(&body).map_err(|error| format!("couldn't {action}: Open Cloud's answer made no sense: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use tiny_http::{Header, Server};

    const TARGET: Target = Target {
        universe: 11,
        place: 22,
        build: None,
    };

    #[derive(Debug, PartialEq)]
    struct Asked {
        method: String,
        url: String,
        key: Option<String>,
        body: Vec<u8>,
    }

    fn asked(method: &str, url: &str, body: &[u8]) -> Asked {
        Asked {
            method: method.to_owned(),
            url: url.to_owned(),
            key: Some("secret".to_owned()),
            body: body.to_vec(),
        }
    }

    /// Plays Open Cloud's part: answers one request with `status` and `body`, and hands back what was asked
    fn fake(status: u16, body: &'static str) -> (Client, thread::JoinHandle<Asked>) {
        let server = Server::http("127.0.0.1:0").unwrap();
        let port = server.server_addr().to_ip().unwrap().port();

        let handle = thread::spawn(move || {
            let mut request = server.recv().unwrap();

            let mut sent = Vec::new();
            request.as_reader().read_to_end(&mut sent).unwrap();

            let asked = Asked {
                method: request.method().to_string(),
                url: request.url().to_owned(),
                key: header(request.headers(), KEY_HEADER),
                body: sent,
            };

            request
                .respond(tiny_http::Response::from_string(body).with_status_code(status))
                .unwrap();

            asked
        });

        (Client::at(&format!("http://127.0.0.1:{port}"), "secret".to_owned()), handle)
    }

    fn header(headers: &[Header], name: &'static str) -> Option<String> {
        headers
            .iter()
            .find(|header| header.field.equiv(name))
            .map(|header| header.value.as_str().to_owned())
    }

    fn progress(task: &'static str) -> TaskState {
        let (client, handle) = fake(200, task);
        let progress = client.progress("universes/11/tasks/abc").unwrap();
        handle.join().unwrap();

        progress
    }

    #[test]
    fn uploads_the_place_as_a_saved_version() {
        let (client, handle) = fake(200, r#"{ "versionNumber": 7 }"#);

        assert_eq!(client.upload(&TARGET, b"<roblox!"), Ok(7));
        assert_eq!(
            handle.join().unwrap(),
            asked("POST", "/universes/v1/11/places/22/versions?versionType=Saved", b"<roblox!")
        );
    }

    #[test]
    fn starts_a_task_in_the_version_it_is_given() {
        let (client, handle) = fake(200, r#"{ "path": "universes/11/tasks/abc", "state": "QUEUED" }"#);

        assert_eq!(client.start(&TARGET, 7, "return 1"), Ok("universes/11/tasks/abc".to_owned()));
        assert_eq!(
            handle.join().unwrap(),
            asked(
                "POST",
                "/cloud/v2/universes/11/places/22/versions/7/luau-execution-session-tasks",
                br#"{"script":"return 1"}"#
            )
        );
    }

    #[test]
    fn asks_after_a_task_by_its_path() {
        let (client, handle) = fake(200, r#"{ "state": "PROCESSING" }"#);

        assert_eq!(client.progress("universes/11/tasks/abc"), Ok(TaskState::Running));
        assert_eq!(handle.join().unwrap(), asked("GET", "/cloud/v2/universes/11/tasks/abc", b""));
    }

    #[test]
    fn reads_how_a_task_ended() {
        assert_eq!(progress(r#"{ "state": "QUEUED" }"#), TaskState::Running);
        assert_eq!(
            progress(r#"{ "state": "COMPLETE", "output": { "results": ["[]"] } }"#),
            TaskState::Complete(vec![json!("[]")])
        );
        assert_eq!(
            progress(r#"{ "state": "FAILED", "error": { "code": "SCRIPT_ERROR", "message": "boom" } }"#),
            TaskState::Failed("boom".to_owned())
        );
        assert_eq!(
            progress(r#"{ "state": "FAILED", "error": { "code": "DEADLINE_EXCEEDED" } }"#),
            TaskState::Failed("DEADLINE_EXCEEDED".to_owned())
        );
        assert_eq!(progress(r#"{ "state": "CANCELLED" }"#), TaskState::Failed("it was cancelled".to_owned()));
    }

    #[test]
    fn a_refusal_carries_what_open_cloud_said() {
        let (client, handle) = fake(429, r#"{ "message": "too many tasks" }"#);
        let problem = client.start(&TARGET, 7, "return 1").unwrap_err();
        handle.join().unwrap();

        assert!(problem.starts_with("couldn't start the task: Open Cloud answered 429"), "{problem}");
        assert!(problem.contains("too many tasks"), "{problem}");
    }

    #[test]
    fn a_key_that_is_turned_away_is_told_what_it_needs() {
        let (client, handle) = fake(403, "{}");
        let problem = client.upload(&TARGET, b"").unwrap_err();
        handle.join().unwrap();

        assert!(problem.contains("403"), "{problem}");
        assert!(problem.contains(PERMISSIONS_HINT), "{problem}");
    }
}

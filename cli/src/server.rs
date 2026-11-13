use crate::manifest::{File, InstancePath, Manifest};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tiny_http::{Method, Request, Response};

/// The plugin polls exactly these, so the two lists have to stay the same
const PORTS: [u16; 2] = [37100, 37101];

/// Raised whenever the plugin and the CLI would stop understanding each other
const PROTOCOL: u32 = 1;

pub struct Timeouts {
    /// How long to wait for a place to take the run
    pub claim: Duration,
    /// How long that place then has to report back
    pub run: Duration,
}

impl Default for Timeouts {
    fn default() -> Timeouts {
        Timeouts {
            claim: Duration::from_secs(10),
            run: Duration::from_secs(120),
        }
    }
}

#[derive(Serialize)]
struct Offer<'a> {
    protocol: u32,
    project: &'a str,
    run: &'a str,
    files: &'a [File],
    specs: Vec<&'a InstancePath>,
}

#[derive(Deserialize)]
struct Claim {
    run: String,
    place: String,
}

/// A place that holds the project, but not the code that is on disk
#[derive(Deserialize, Debug)]
pub struct Mismatch {
    run: String,
    pub place: String,
    pub missing: Vec<InstancePath>,
    pub differing: Vec<InstancePath>,
}

#[derive(Deserialize)]
struct Report {
    run: String,
    results: Option<Value>,
    error: Option<String>,
}

#[derive(Debug)]
pub enum Outcome {
    Results(Value),
    Failed { place: String, message: String },
    Unclaimed(Vec<Mismatch>),
    Abandoned { place: String },
}

pub struct Server {
    http: tiny_http::Server,
    port: u16,
}

impl Server {
    pub fn open() -> Result<Server, String> {
        PORTS.into_iter().find_map(Server::bind).ok_or_else(|| {
            format!(
                "ports {} to {} are all in use",
                PORTS[0],
                PORTS[PORTS.len() - 1]
            )
        })
    }

    fn bind(port: u16) -> Option<Server> {
        let http = tiny_http::Server::http(("127.0.0.1", port)).ok()?;

        // Read back, since the tests bind port 0 to be given any free one
        let port = http.server_addr().to_ip()?.port();

        Some(Server { http, port })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Offers one run of the project to whichever place holds it, and waits for how that goes
    pub fn serve(&self, manifest: &Manifest, timeouts: Timeouts) -> Result<Outcome, String> {
        let run = run_id();
        let offer = serde_json::to_string(&Offer {
            protocol: PROTOCOL,
            project: &manifest.project,
            run: &run,
            files: &manifest.files,
            specs: manifest.specs(),
        })
        .map_err(|error| format!("couldn't write the offer: {error}"))?;

        let mut claimant: Option<String> = None;
        let mut mismatches: Vec<Mismatch> = Vec::new();
        let mut deadline = Instant::now() + timeouts.claim;

        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(match claimant {
                    Some(place) => Outcome::Abandoned { place },
                    None => Outcome::Unclaimed(mismatches),
                });
            }

            let received = self
                .http
                .recv_timeout(remaining)
                .map_err(|error| format!("the connection to Studio failed: {error}"))?;
            let Some(mut request) = received else {
                continue;
            };

            if !is_local(&request, self.port) {
                respond(request, 403);
                continue;
            }

            let method = request.method().clone();
            let url = request.url().to_owned();
            let mut body = String::new();
            if request.as_reader().read_to_string(&mut body).is_err() {
                respond(request, 400);
                continue;
            }

            match (&method, url.as_str()) {
                (Method::Get, "/offer") => match claimant {
                    None => respond_with(request, 200, &offer),
                    Some(_) => respond(request, 410),
                },

                (Method::Post, "/claim") => match serde_json::from_str::<Claim>(&body) {
                    Ok(claim) if claim.run == run && claimant.is_none() => {
                        eprintln!("litmus: running in {}", claim.place);
                        claimant = Some(claim.place);
                        deadline = Instant::now() + timeouts.run;
                        respond(request, 200);
                    }
                    Ok(_) => respond(request, 409),
                    Err(_) => respond(request, 400),
                },

                (Method::Post, "/mismatch") => match serde_json::from_str::<Mismatch>(&body) {
                    Ok(mismatch) if mismatch.run == run => {
                        mismatches.retain(|earlier| earlier.place != mismatch.place);
                        mismatches.push(mismatch);
                        respond(request, 200);
                    }
                    Ok(_) => respond(request, 409),
                    Err(_) => respond(request, 400),
                },

                (Method::Post, "/result") => match serde_json::from_str::<Report>(&body) {
                    Ok(report) if report.run == run => {
                        respond(request, 200);

                        return Ok(match report.results {
                            Some(results) => Outcome::Results(results),
                            None => Outcome::Failed {
                                place: claimant.unwrap_or_else(|| "Studio".to_owned()),
                                message: report.error.unwrap_or_else(|| "it gave no reason".to_owned()),
                            },
                        });
                    }
                    Ok(_) => respond(request, 409),
                    Err(_) => respond(request, 400),
                },

                _ => respond(request, 404),
            }
        }
    }
}

/// Tells this run's requests apart from a plugin still answering an earlier run on the same port
fn run_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos());

    format!("{nanos:x}-{:x}", std::process::id())
}

/// A web page can only reach this port under a domain name of its own, and that name is what it sends as the host
fn is_local(request: &Request, port: u16) -> bool {
    request.headers().iter().any(|header| {
        let host = header.value.as_str();
        header.field.equiv("Host") && (host == "127.0.0.1" || host == format!("127.0.0.1:{port}"))
    })
}

fn respond(request: Request, status: u16) {
    respond_with(request, status, "{}");
}

fn respond_with(request: Request, status: u16, body: &str) {
    // A plugin that hangs up early will simply ask again on its next poll
    let _ = request.respond(Response::from_string(body).with_status_code(status));
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::thread;

    fn manifest() -> Manifest {
        Manifest {
            project: "demo".to_owned(),
            files: vec![File {
                path: vec!["ReplicatedStorage".to_owned(), "Thing.spec".to_owned()],
                hash: "00".to_owned(),
                file: "Thing.spec.luau".into(),
            }],
        }
    }

    /// Plays the plugin's part: one request, returning the status and the body
    fn send(port: u16, method: &str, route: &str, body: &str) -> (u16, String) {
        send_as(&format!("127.0.0.1:{port}"), port, method, route, body)
    }

    fn send_as(host: &str, port: u16, method: &str, route: &str, body: &str) -> (u16, String) {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(
            stream,
            "{method} {route} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        )
        .unwrap();

        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();

        let status: u16 = response.split(' ').nth(1).unwrap().parse().unwrap();
        let body = response.split_once("\r\n\r\n").map_or("", |(_, body)| body);

        (status, body.to_owned())
    }

    fn serve(timeouts: Timeouts) -> (u16, thread::JoinHandle<Outcome>) {
        let server = Server::bind(0).unwrap();
        let port = server.port();
        let handle = thread::spawn(move || server.serve(&manifest(), timeouts).unwrap());

        (port, handle)
    }

    #[test]
    fn a_claimed_run_returns_its_results() {
        let (port, handle) = serve(Timeouts::default());

        let (status, body) = send(port, "GET", "/offer", "");
        let offer: Value = serde_json::from_str(&body).unwrap();
        let run = offer["run"].as_str().unwrap();

        assert_eq!(status, 200);
        assert_eq!(offer["protocol"], 1);
        assert_eq!(offer["project"], "demo");
        assert_eq!(offer["files"][0]["path"], json!(["ReplicatedStorage", "Thing.spec"]));
        assert_eq!(offer["specs"], json!([["ReplicatedStorage", "Thing.spec"]]));

        let claim = json!({ "run": run, "place": "First" }).to_string();
        assert_eq!(send(port, "POST", "/claim", &claim).0, 200);
        assert_eq!(send(port, "POST", "/claim", &claim).0, 409);
        assert_eq!(send(port, "GET", "/offer", "").0, 410);

        let report = json!({ "run": run, "results": [{ "path": "Thing.spec" }] }).to_string();
        assert_eq!(send(port, "POST", "/result", &report).0, 200);

        match handle.join().unwrap() {
            Outcome::Results(results) => assert_eq!(results, json!([{ "path": "Thing.spec" }])),
            other => panic!("expected results, got {other:?}"),
        }
    }

    #[test]
    fn a_run_that_fails_in_studio_carries_the_reason() {
        let (port, handle) = serve(Timeouts::default());

        let offer: Value = serde_json::from_str(&send(port, "GET", "/offer", "").1).unwrap();
        let run = offer["run"].as_str().unwrap();

        send(port, "POST", "/claim", &json!({ "run": run, "place": "First" }).to_string());
        send(port, "POST", "/result", &json!({ "run": run, "error": "no lib" }).to_string());

        match handle.join().unwrap() {
            Outcome::Failed { place, message } => {
                assert_eq!(place, "First");
                assert_eq!(message, "no lib");
            }
            other => panic!("expected a failure, got {other:?}"),
        }
    }

    #[test]
    fn an_unclaimed_run_says_which_places_were_out_of_date() {
        let (port, handle) = serve(Timeouts {
            claim: Duration::from_millis(500),
            run: Duration::from_secs(1),
        });

        let offer: Value = serde_json::from_str(&send(port, "GET", "/offer", "").1).unwrap();
        let mismatch = json!({
            "run": offer["run"],
            "place": "Stale",
            "missing": [],
            "differing": [["ReplicatedStorage", "Thing.spec"]],
        })
        .to_string();

        assert_eq!(send(port, "POST", "/mismatch", &mismatch).0, 200);
        assert_eq!(send(port, "POST", "/mismatch", &mismatch).0, 200);

        match handle.join().unwrap() {
            Outcome::Unclaimed(mismatches) => {
                assert_eq!(mismatches.len(), 1);
                assert_eq!(mismatches[0].place, "Stale");
                assert_eq!(mismatches[0].differing.len(), 1);
            }
            other => panic!("expected no claim, got {other:?}"),
        }
    }

    #[test]
    fn requests_under_another_host_name_are_refused() {
        let (port, handle) = serve(Timeouts {
            claim: Duration::from_millis(500),
            run: Duration::from_secs(1),
        });

        assert_eq!(send_as("evil.example", port, "GET", "/offer", "").0, 403);
        assert_eq!(send_as(&format!("evil.example:{port}"), port, "GET", "/offer", "").0, 403);
        assert_eq!(send_as("127.0.0.1", port, "GET", "/offer", "").0, 200);

        assert!(matches!(handle.join().unwrap(), Outcome::Unclaimed(_)));
    }

    #[test]
    fn requests_for_another_run_are_refused() {
        let (port, handle) = serve(Timeouts {
            claim: Duration::from_millis(500),
            run: Duration::from_secs(1),
        });

        let claim = json!({ "run": "someone-else", "place": "First" }).to_string();
        assert_eq!(send(port, "POST", "/claim", &claim).0, 409);
        assert_eq!(send(port, "GET", "/nowhere", "").0, 404);

        assert!(matches!(handle.join().unwrap(), Outcome::Unclaimed(_)));
    }
}

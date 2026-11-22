use crate::manifest::{InstancePath, Manifest, Script};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tiny_http::{Method, Request, Response};

const PLUGIN_PORTS: [u16; 2] = [37100, 37101];

const PLUGIN_PROTOCOL: u32 = 3;

pub struct Timeouts {
    pub until_claimed: Duration,
    pub until_reported: Duration,
}

impl Default for Timeouts {
    fn default() -> Timeouts {
        Timeouts {
            until_claimed: Duration::from_secs(10),
            until_reported: Duration::from_secs(120),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunOffer<'a> {
    protocol: u32,
    kind: &'static str,
    project: &'a str,
    run_id: &'a str,
    files: &'a [Script],
    specs: Vec<&'a InstancePath>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Envelope<T> {
    run_id: String,
    #[serde(flatten)]
    message: T,
}

#[derive(Deserialize)]
struct Claim {
    place: String,
}

#[derive(Deserialize, Debug, PartialEq)]
pub struct Mismatch {
    pub place: String,
    pub missing: Vec<InstancePath>,
    pub differing: Vec<InstancePath>,
}

#[derive(Deserialize)]
struct Completion {
    results: Option<Value>,
    error: Option<String>,
}

#[derive(Debug, PartialEq)]
pub enum Outcome {
    Results(Value),
    Failed { place: String, message: String },
    Unclaimed(Vec<Mismatch>),
    Abandoned { place: String },
}

struct Exchange {
    run_id: String,
    offer: String,
    claimant: Option<String>,
    mismatches: Vec<Mismatch>,
}

enum RunAnswer<'a> {
    Offer(&'a str),
    Status(u16),
    Claimed(&'a str),
    Finished(Outcome),
}

impl Exchange {
    fn new(manifest: &Manifest) -> Result<Exchange, String> {
        let run_id = new_run_id();
        let offer = serde_json::to_string(&RunOffer {
            protocol: PLUGIN_PROTOCOL,
            kind: "run",
            project: &manifest.project,
            run_id: &run_id,
            files: &manifest.scripts,
            specs: manifest.specs(),
        })
        .map_err(|error| format!("couldn't write the offer: {error}"))?;

        Ok(Exchange {
            run_id,
            offer,
            claimant: None,
            mismatches: Vec::new(),
        })
    }

    fn answer(&mut self, method: &Method, url: &str, body: &str) -> RunAnswer<'_> {
        match (method, url) {
            (Method::Get, "/offer") => match self.claimant {
                None => RunAnswer::Offer(&self.offer),
                Some(_) => RunAnswer::Status(410),
            },

            (Method::Post, "/claim") => match read::<Claim>(&self.run_id, body) {
                Ok(claim) if self.claimant.is_none() => RunAnswer::Claimed(self.claimant.insert(claim.place)),
                Ok(_) => RunAnswer::Status(409),
                Err(status) => RunAnswer::Status(status),
            },

            (Method::Post, "/mismatch") => match read::<Mismatch>(&self.run_id, body) {
                Ok(mismatch) => {
                    self.mismatches.retain(|earlier| earlier.place != mismatch.place);
                    self.mismatches.push(mismatch);
                    RunAnswer::Status(200)
                }
                Err(status) => RunAnswer::Status(status),
            },

            (Method::Post, "/result") => match (read::<Completion>(&self.run_id, body), self.claimant.clone()) {
                (Ok(completion), Some(place)) => RunAnswer::Finished(match completion.results {
                    Some(results) => Outcome::Results(results),
                    None => Outcome::Failed {
                        place,
                        message: completion.error.unwrap_or_else(|| "it gave no reason".to_owned()),
                    },
                }),
                (Ok(_), None) => RunAnswer::Status(409),
                (Err(status), _) => RunAnswer::Status(status),
            },

            _ => RunAnswer::Status(404),
        }
    }

    fn expire(self) -> Outcome {
        match self.claimant {
            Some(place) => Outcome::Abandoned { place },
            None => Outcome::Unclaimed(self.mismatches),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ShowOffer<'a> {
    protocol: u32,
    kind: &'static str,
    project: &'a str,
    run_id: &'a str,
}

#[derive(Deserialize)]
struct Collect {
    place: String,
}

struct Showing<'a> {
    run_id: String,
    offer: String,
    run: &'a str,
}

enum ShowAnswer<'a> {
    Offer(&'a str),
    Run { place: String, run: &'a str },
    Status(u16),
}

impl<'a> Showing<'a> {
    fn new(project: &str, run: &'a str) -> Result<Showing<'a>, String> {
        let run_id = new_run_id();
        let offer = serde_json::to_string(&ShowOffer {
            protocol: PLUGIN_PROTOCOL,
            kind: "show",
            project,
            run_id: &run_id,
        })
        .map_err(|error| format!("couldn't write the offer: {error}"))?;

        Ok(Showing { run_id, offer, run })
    }

    fn answer(&self, method: &Method, url: &str, body: &str) -> ShowAnswer<'_> {
        match (method, url) {
            (Method::Get, "/offer") => ShowAnswer::Offer(&self.offer),

            (Method::Post, "/collect") => match read::<Collect>(&self.run_id, body) {
                Ok(collect) => ShowAnswer::Run {
                    place: collect.place,
                    run: self.run,
                },
                Err(status) => ShowAnswer::Status(status),
            },

            _ => ShowAnswer::Status(404),
        }
    }
}

fn read<T: DeserializeOwned>(run_id: &str, body: &str) -> Result<T, u16> {
    let envelope: Envelope<T> = serde_json::from_str(body).map_err(|_| 400u16)?;
    if envelope.run_id != run_id {
        return Err(409);
    }

    Ok(envelope.message)
}

pub struct Server {
    http: tiny_http::Server,
    port: u16,
}

impl Server {
    pub fn open() -> Result<Server, String> {
        let [first, second] = PLUGIN_PORTS;

        PLUGIN_PORTS
            .into_iter()
            .find_map(Server::bind)
            .ok_or_else(|| format!("ports {first} and {second} are both in use"))
    }

    fn bind(port: u16) -> Option<Server> {
        let http = tiny_http::Server::http(("127.0.0.1", port)).ok()?;

        let port = http.server_addr().to_ip()?.port();

        Some(Server { http, port })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn offer_run(
        &self,
        manifest: &Manifest,
        timeouts: Timeouts,
        mut on_claim: impl FnMut(&str),
    ) -> Result<Outcome, String> {
        let mut exchange = Exchange::new(manifest)?;
        let mut deadline = Instant::now() + timeouts.until_claimed;

        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(exchange.expire());
            }

            let Some((request, body)) = self.receive(remaining)? else {
                continue;
            };

            match exchange.answer(request.method(), request.url(), &body) {
                RunAnswer::Offer(offer) => respond_with(request, 200, offer),
                RunAnswer::Status(status) => respond(request, status),
                RunAnswer::Claimed(place) => {
                    respond(request, 200);
                    on_claim(place);
                    deadline = Instant::now() + timeouts.until_reported;
                }
                RunAnswer::Finished(outcome) => {
                    respond(request, 200);
                    return Ok(outcome);
                }
            }
        }
    }

    pub fn offer_show(
        &self,
        project: &str,
        run: &str,
        window: Duration,
        mut on_collect: impl FnMut(&str),
    ) -> Result<(), String> {
        let showing = Showing::new(project, run)?;
        let deadline = Instant::now() + window;

        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(());
            }

            let Some((request, body)) = self.receive(remaining)? else {
                continue;
            };

            match showing.answer(request.method(), request.url(), &body) {
                ShowAnswer::Offer(offer) => respond_with(request, 200, offer),
                ShowAnswer::Status(status) => respond(request, status),
                ShowAnswer::Run { place, run } => {
                    respond_with(request, 200, run);
                    on_collect(&place);
                }
            }
        }
    }

    fn receive(&self, patience: Duration) -> Result<Option<(Request, String)>, String> {
        let received = self
            .http
            .recv_timeout(patience)
            .map_err(|error| format!("the connection to Studio failed: {error}"))?;
        let Some(mut request) = received else {
            return Ok(None);
        };

        if !is_safe_from_rebinding(&request, self.port) {
            respond(request, 403);
            return Ok(None);
        }

        let mut body = String::new();
        if request.as_reader().read_to_string(&mut body).is_err() {
            respond(request, 400);
            return Ok(None);
        }

        Ok(Some((request, body)))
    }
}

fn new_run_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos());

    format!("{nanos:x}-{:x}", std::process::id())
}

fn is_safe_from_rebinding(request: &Request, port: u16) -> bool {
    request.headers().iter().any(|header| {
        let host = header.value.as_str();
        header.field.equiv("Host") && (host == "127.0.0.1" || host == format!("127.0.0.1:{port}"))
    })
}

fn respond(request: Request, status: u16) {
    respond_with(request, status, "{}");
}

fn respond_with(request: Request, status: u16, body: &str) {
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
            scripts: vec![Script {
                path: vec!["ReplicatedStorage".to_owned(), "Thing.spec".to_owned()],
                hash: "00".to_owned(),
                file: "Thing.spec.luau".into(),
            }],
        }
    }

    fn exchange() -> Exchange {
        Exchange::new(&manifest()).unwrap()
    }

    fn post(exchange: &mut Exchange, route: &str, mut message: Value) -> u16 {
        message["runId"] = json!(exchange.run_id);
        status_of(exchange.answer(&Method::Post, route, &message.to_string()))
    }

    fn status_of(answer: RunAnswer) -> u16 {
        match answer {
            RunAnswer::Status(status) => status,
            RunAnswer::Offer(_) | RunAnswer::Claimed(_) | RunAnswer::Finished(_) => 200,
        }
    }

    #[test]
    fn the_offer_names_the_run_and_what_to_compare() {
        let mut exchange = exchange();
        let RunAnswer::Offer(offer) = exchange.answer(&Method::Get, "/offer", "") else {
            panic!("expected the offer");
        };
        let offer: Value = serde_json::from_str(offer).unwrap();

        assert_eq!(offer["protocol"], 3);
        assert_eq!(offer["kind"], "run");
        assert_eq!(offer["project"], "demo");
        assert_eq!(offer["runId"], json!(exchange.run_id));
        assert_eq!(offer["files"], json!([{ "path": ["ReplicatedStorage", "Thing.spec"], "hash": "00" }]));
        assert_eq!(offer["specs"], json!([["ReplicatedStorage", "Thing.spec"]]));
    }

    #[test]
    fn the_first_claim_wins_and_ends_the_offer() {
        let mut exchange = exchange();
        let claim = json!({ "runId": exchange.run_id, "place": "First" }).to_string();

        assert!(matches!(exchange.answer(&Method::Post, "/claim", &claim), RunAnswer::Claimed("First")));
        assert_eq!(post(&mut exchange, "/claim", json!({ "place": "Second" })), 409);
        assert_eq!(status_of(exchange.answer(&Method::Get, "/offer", "")), 410);
    }

    #[test]
    fn a_claimed_run_finishes_with_its_results() {
        let mut exchange = exchange();
        post(&mut exchange, "/claim", json!({ "place": "First" }));

        let report = json!({ "runId": exchange.run_id, "results": [{ "path": "Thing.spec" }] }).to_string();
        let RunAnswer::Finished(outcome) = exchange.answer(&Method::Post, "/result", &report) else {
            panic!("expected the run to finish");
        };

        assert_eq!(outcome, Outcome::Results(json!([{ "path": "Thing.spec" }])));
    }

    #[test]
    fn a_run_that_fails_in_studio_carries_the_reason() {
        let mut exchange = exchange();
        post(&mut exchange, "/claim", json!({ "place": "First" }));

        let report = json!({ "runId": exchange.run_id, "error": "no lib" }).to_string();
        let RunAnswer::Finished(outcome) = exchange.answer(&Method::Post, "/result", &report) else {
            panic!("expected the run to finish");
        };

        assert_eq!(
            outcome,
            Outcome::Failed {
                place: "First".to_owned(),
                message: "no lib".to_owned()
            }
        );
    }

    #[test]
    fn a_result_nobody_claimed_is_refused() {
        let mut exchange = exchange();

        assert_eq!(post(&mut exchange, "/result", json!({ "results": [] })), 409);
    }

    #[test]
    fn messages_that_are_not_for_this_run_are_refused() {
        let mut exchange = exchange();
        let stranger = json!({ "runId": "someone-else", "place": "First" }).to_string();

        assert_eq!(status_of(exchange.answer(&Method::Post, "/claim", &stranger)), 409);
        assert_eq!(status_of(exchange.answer(&Method::Post, "/claim", "not json")), 400);
        assert_eq!(status_of(exchange.answer(&Method::Get, "/nowhere", "")), 404);
    }

    #[test]
    fn an_unclaimed_run_keeps_the_latest_word_from_each_stale_place() {
        let mut exchange = exchange();
        let stale = |differing: Value| json!({ "place": "Stale", "missing": [], "differing": differing });

        assert_eq!(post(&mut exchange, "/mismatch", stale(json!([["A"], ["B"]]))), 200);
        assert_eq!(post(&mut exchange, "/mismatch", stale(json!([["A"]]))), 200);

        assert_eq!(
            exchange.expire(),
            Outcome::Unclaimed(vec![Mismatch {
                place: "Stale".to_owned(),
                missing: vec![],
                differing: vec![vec!["A".to_owned()]],
            }])
        );
    }

    #[test]
    fn a_claimed_run_that_never_reports_is_abandoned() {
        let mut exchange = exchange();
        post(&mut exchange, "/claim", json!({ "place": "First" }));

        assert_eq!(
            exchange.expire(),
            Outcome::Abandoned {
                place: "First".to_owned()
            }
        );
    }

    fn showing() -> Showing<'static> {
        Showing::new("demo", r#"{"results":{"specs":[]}}"#).unwrap()
    }

    fn collected(showing: &Showing, place: &str) -> Option<String> {
        let collect = json!({ "runId": showing.run_id, "place": place }).to_string();

        match showing.answer(&Method::Post, "/collect", &collect) {
            ShowAnswer::Run { place, run } => Some(format!("{place}: {run}")),
            _ => None,
        }
    }

    #[test]
    fn a_finished_run_is_offered_as_one_to_show() {
        let showing = showing();
        let ShowAnswer::Offer(offer) = showing.answer(&Method::Get, "/offer", "") else {
            panic!("expected the offer");
        };
        let offer: Value = serde_json::from_str(offer).unwrap();

        assert_eq!(
            offer,
            json!({ "protocol": 3, "kind": "show", "project": "demo", "runId": showing.run_id })
        );
    }

    #[test]
    fn every_place_that_asks_is_handed_the_run_and_the_offer_stands() {
        let showing = showing();
        let run = r#"{"results":{"specs":[]}}"#;

        assert_eq!(collected(&showing, "First"), Some(format!("First: {run}")));
        assert_eq!(collected(&showing, "Second"), Some(format!("Second: {run}")));
        assert!(matches!(showing.answer(&Method::Get, "/offer", ""), ShowAnswer::Offer(_)));
    }

    #[test]
    fn a_shown_run_is_not_handed_to_whoever_asks_for_another() {
        let showing = showing();
        let stranger = json!({ "runId": "someone-else", "place": "First" }).to_string();

        assert!(matches!(showing.answer(&Method::Post, "/collect", &stranger), ShowAnswer::Status(409)));
        assert!(matches!(showing.answer(&Method::Post, "/collect", "not json"), ShowAnswer::Status(400)));
        assert!(matches!(showing.answer(&Method::Post, "/claim", &stranger), ShowAnswer::Status(404)));
    }

    fn send(host: &str, port: u16, method: &str, route: &str, body: &str) -> (u16, String) {
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

    fn serve(timeouts: Timeouts) -> (u16, thread::JoinHandle<(Outcome, Vec<String>)>) {
        let server = Server::bind(0).unwrap();
        let port = server.port();

        let handle = thread::spawn(move || {
            let mut claimed = Vec::new();
            let outcome = server
                .offer_run(&manifest(), timeouts, |place| claimed.push(place.to_owned()))
                .unwrap();

            (outcome, claimed)
        });

        (port, handle)
    }

    #[test]
    fn a_run_is_served_over_http() {
        let (port, handle) = serve(Timeouts::default());
        let host = format!("127.0.0.1:{port}");

        let (status, body) = send(&host, port, "GET", "/offer", "");
        let offer: Value = serde_json::from_str(&body).unwrap();
        assert_eq!(status, 200);

        let claim = json!({ "runId": offer["runId"], "place": "First" }).to_string();
        let report = json!({ "runId": offer["runId"], "results": [] }).to_string();
        assert_eq!(send(&host, port, "POST", "/claim", &claim).0, 200);
        assert_eq!(send(&host, port, "POST", "/result", &report).0, 200);

        let (outcome, claimed) = handle.join().unwrap();
        assert_eq!(outcome, Outcome::Results(json!([])));
        assert_eq!(claimed, ["First"]);
    }

    #[test]
    fn a_finished_run_is_shown_over_http_until_the_window_shuts() {
        let server = Server::bind(0).unwrap();
        let port = server.port();
        let host = format!("127.0.0.1:{port}");

        let handle = thread::spawn(move || {
            let mut collected = Vec::new();
            server
                .offer_show("demo", r#"{"results":{"specs":[]}}"#, Duration::from_millis(500), |place| {
                    collected.push(place.to_owned());
                })
                .unwrap();

            collected
        });

        let (status, body) = send(&host, port, "GET", "/offer", "");
        let offer: Value = serde_json::from_str(&body).unwrap();
        assert_eq!(status, 200);

        let collect = |place: &str| json!({ "runId": offer["runId"], "place": place }).to_string();
        let run = (200, r#"{"results":{"specs":[]}}"#.to_owned());
        assert_eq!(send(&host, port, "POST", "/collect", &collect("First")), run);
        assert_eq!(send(&host, port, "POST", "/collect", &collect("Second")), run);

        assert_eq!(handle.join().unwrap(), ["First", "Second"]);
    }

    #[test]
    fn requests_under_another_host_name_are_refused() {
        let (port, handle) = serve(Timeouts {
            until_claimed: Duration::from_millis(500),
            until_reported: Duration::from_secs(1),
        });

        assert_eq!(send("evil.example", port, "GET", "/offer", "").0, 403);
        assert_eq!(send(&format!("evil.example:{port}"), port, "GET", "/offer", "").0, 403);
        assert_eq!(send("127.0.0.1", port, "GET", "/offer", "").0, 200);

        assert_eq!(handle.join().unwrap().0, Outcome::Unclaimed(vec![]));
    }
}

use crate::manifest::InstancePath;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct Failure {
    pub message: String,
    pub source: InstancePath,
    pub line: u32,
}

#[derive(Deserialize)]
pub struct TestResult {
    pub name: String,
    pub groups: Vec<String>,
    pub failure: Option<Failure>,
}

#[derive(Deserialize)]
pub struct SpecResult {
    pub path: InstancePath,
    pub tests: Vec<TestResult>,

    /// Set when the spec itself didn't load, in which case none of its tests ran
    pub failure: Option<Failure>,
}

impl SpecResult {
    pub fn failed_tests(&self) -> impl Iterator<Item = (&TestResult, &Failure)> {
        self.tests
            .iter()
            .filter_map(|test| test.failure.as_ref().map(|failure| (test, failure)))
    }
}

#[derive(Default, Debug, PartialEq)]
pub struct Tally {
    pub passed_specs: usize,
    pub failed_specs: usize,
    pub errored_specs: usize,
    pub passed_tests: usize,
    pub failed_tests: usize,
}

impl Tally {
    pub fn of(results: &[SpecResult]) -> Tally {
        let mut tally = Tally::default();

        for spec in results {
            let failed = spec.failed_tests().count();
            tally.passed_tests += spec.tests.len() - failed;
            tally.failed_tests += failed;

            if spec.failure.is_some() {
                tally.errored_specs += 1;
            } else if failed > 0 {
                tally.failed_specs += 1;
            } else {
                tally.passed_specs += 1;
            }
        }

        tally
    }

    pub fn passed(&self) -> bool {
        self.failed_specs == 0 && self.errored_specs == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tally(results: &str) -> Tally {
        let results: Vec<SpecResult> = serde_json::from_str(results).unwrap();
        Tally::of(&results)
    }

    #[test]
    fn counts_each_kind_of_spec() {
        let failure = r#"{ "message": "m", "source": ["s"], "line": 1, "trace": "t" }"#;
        let tally = tally(&format!(
            r#"[
                {{ "path": ["a"], "tests": [{{ "name": "one", "groups": [] }}] }},
                {{ "path": ["b"], "tests": [
                    {{ "name": "one", "groups": [] }},
                    {{ "name": "two", "groups": [], "failure": {failure} }}
                ] }},
                {{ "path": ["c"], "tests": [], "failure": {failure} }}
            ]"#
        ));

        assert_eq!(
            tally,
            Tally {
                passed_specs: 1,
                failed_specs: 1,
                errored_specs: 1,
                passed_tests: 2,
                failed_tests: 1,
            }
        );
        assert!(!tally.passed());
    }

    #[test]
    fn passes_when_every_spec_did() {
        assert!(tally(r#"[{ "path": ["a"], "tests": [{ "name": "one", "groups": [] }] }]"#).passed());
    }

    #[test]
    fn does_not_pass_when_a_spec_never_loaded() {
        let results = r#"[{ "path": ["a"], "tests": [], "failure": { "message": "m", "source": ["s"], "line": 1 } }]"#;
        assert!(!tally(results).passed());
    }
}

use crate::cloud::Place;
use serde::Deserialize;
use std::fs;
use std::io::ErrorKind;
use std::path::Path;

const FILE: &str = "litmus.toml";

#[derive(Deserialize, Default, Debug, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Config {
    cloud: Option<Place>,
}

impl Config {
    pub fn read(project_dir: &Path) -> Result<Config, String> {
        match fs::read_to_string(project_dir.join(FILE)) {
            Ok(text) => Config::parse(&text),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(Config::default()),
            Err(error) => Err(format!("couldn't read {FILE}: {error}")),
        }
    }

    fn parse(text: &str) -> Result<Config, String> {
        toml::from_str(text).map_err(|error| format!("couldn't read {FILE}: {error}"))
    }

    pub fn cloud(self) -> Result<Place, String> {
        self.cloud.ok_or_else(|| {
            format!(
                "{FILE} names no place for --cloud to run in; \
                 it needs a [cloud] table with the experience as `universe` and its place as `place`"
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_where_a_cloud_run_happens() {
        let config = Config::parse("[cloud]\nuniverse = 11\nplace = 22\n").unwrap();

        assert_eq!(
            config.cloud(),
            Ok(Place {
                universe: 11,
                place: 22,
            })
        );
    }

    #[test]
    fn a_project_without_the_file_has_no_place_for_a_cloud_run() {
        let nowhere = Path::new("a folder that doesn't exist");

        assert_eq!(Config::read(nowhere), Ok(Config::default()));
        assert!(Config::default().cloud().unwrap_err().contains("[cloud]"));
        assert!(Config::parse("").unwrap().cloud().is_err());
    }

    #[test]
    fn refuses_a_place_it_could_not_run_in() {
        assert!(Config::parse("[cloud]\nuniverse = 11\n").is_err());
        assert!(Config::parse("[cloud]\nuniverse = \"eleven\"\nplace = 22\n").is_err());
        assert!(Config::parse("[cloud]\nuniverse = -11\nplace = 22\n").is_err());
    }

    #[test]
    fn refuses_a_name_it_does_not_know() {
        assert!(Config::parse("[cloud]\nuniverse = 11\nplace = 22\nplaec = 33\n").is_err());
        assert!(Config::parse("[clowd]\nuniverse = 11\nplace = 22\n").is_err());
    }
}

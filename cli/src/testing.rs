use std::fs;
use std::ops::Deref;
use std::path::{Path, PathBuf};

pub struct TempProject {
    dir: PathBuf,
}

impl TempProject {
    pub fn new(name: &str) -> TempProject {
        let dir = std::env::temp_dir().join(format!("litmus-{}-{name}", std::process::id()));

        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        TempProject { dir }
    }

    pub fn write(&self, file: &str, text: &str) {
        let file = self.dir.join(file);

        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(file, text).unwrap();
    }
}

impl Deref for TempProject {
    type Target = Path;

    fn deref(&self) -> &Path {
        &self.dir
    }
}

impl AsRef<Path> for TempProject {
    fn as_ref(&self) -> &Path {
        &self.dir
    }
}

impl Drop for TempProject {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

pub fn without_colour(text: &str) -> String {
    anstream::adapter::strip_str(text).to_string()
}

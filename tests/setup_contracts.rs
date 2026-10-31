use std::{
    env,
    fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
    time::{SystemTime, UNIX_EPOCH},
};

struct TempRoot(PathBuf);

impl TempRoot {
    fn new() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = env::temp_dir().join(format!("oreslang-ssr-{}-{nonce}", std::process::id()));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}

impl Drop for TempRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

struct Fixture {
    _temp: TempRoot,
    root: PathBuf,
    compiler: PathBuf,
    launcher: PathBuf,
    bin: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let temp = TempRoot::new();
        let root = temp.0.clone();
        fs::create_dir(root.join("scripts")).unwrap();
        fs::copy(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("scripts/setup.sh"),
            root.join("scripts/setup.sh"),
        )
        .unwrap();

        let compiler = root.join(".work/compiler");
        fs::create_dir_all(&compiler).unwrap();
        fs::write(compiler.join("pom.xml"), "<project/>").unwrap();

        let fixture = Self {
            _temp: temp,
            root: root.clone(),
            compiler: compiler.clone(),
            launcher: root.join(".work/ores"),
            bin: root.join("bin"),
        };
        fixture.git(&["init", "-q"]);
        fixture.git(&["add", "."]);
        fixture.git(&[
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "fixture",
        ]);
        fs::write(root.join("compiler.lock"), fixture.git(&["rev-parse", "HEAD"])).unwrap();
        fs::write(
            root.join("compiler-tree.txt"),
            fixture.git(&["rev-parse", "HEAD^{tree}"]),
        )
        .unwrap();

        fs::write(&fixture.launcher, "old executable").unwrap();
        fs::create_dir(&fixture.bin).unwrap();
        let mvn = fixture.bin.join("mvn");
        fs::write(
            &mvn,
            "#!/bin/sh\nprintf \"%s\\n\" \"$@\" > \"$SETUP_ARGS\"\nexit \"${SETUP_FAIL:-0}\"\n",
        )
        .unwrap();
        let mut perms = fs::metadata(&mvn).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&mvn, perms).unwrap();

        fixture
    }

    fn git(&self, args: &[&str]) -> String {
        let output = Command::new("git")
            .arg("-C")
            .arg(&self.compiler)
            .args(args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    }

    fn run_setup(&self, fail: bool) -> Output {
        let old_path = env::var("PATH").unwrap_or_default();
        Command::new("bash")
            .arg("scripts/setup.sh")
            .current_dir(&self.root)
            .env("PATH", format!("{}:{old_path}", self.bin.display()))
            .env("SETUP_ARGS", self.root.join("args"))
            .env("SETUP_FAIL", if fail { "1" } else { "0" })
            .output()
            .unwrap()
    }
}

#[test]
fn success_cleans_classes_and_publishes_launcher() {
    let f = Fixture::new();
    let result = f.run_setup(false);
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let args = fs::read_to_string(f.root.join("args")).unwrap();
    assert!(args.contains("clean\npackage\n"));
    let launcher = fs::read_to_string(&f.launcher).unwrap();
    assert!(launcher.contains("exec java"));
    assert_ne!(
        fs::metadata(&f.launcher).unwrap().permissions().mode() & 0o111,
        0
    );
}

#[test]
fn failed_build_removes_stale_launcher() {
    let f = Fixture::new();
    assert!(!f.run_setup(true).status.success());
    assert!(!f.launcher.exists());
}

#[test]
fn dirty_input_is_preserved_without_launcher() {
    let f = Fixture::new();
    fs::write(f.compiler.join("pom.xml"), "local changes").unwrap();
    assert!(!f.run_setup(false).status.success());
    assert_eq!(
        fs::read_to_string(f.compiler.join("pom.xml")).unwrap(),
        "local changes"
    );
    assert!(!f.launcher.exists());
    assert!(!f.root.join("args").exists());
}

#[test]
fn symlink_input_is_rejected_before_build() {
    let f = Fixture::new();
    let target = f.root.join("saved-compiler");
    fs::rename(&f.compiler, &target).unwrap();
    symlink(&target, &f.compiler).unwrap();
    assert!(!f.run_setup(false).status.success());
    assert!(!f.root.join("args").exists());
}

#[test]
fn symlink_workdir_rejected_without_deleting_redirected_launcher() {
    let f = Fixture::new();
    let work = f.root.join(".work");
    let retained = f.root.join("saved-work");
    fs::rename(&work, &retained).unwrap();
    symlink(&retained, &work).unwrap();
    let original = fs::read_to_string(retained.join("ores")).unwrap();

    let output = f.run_setup(false);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("work directory must not be a symlink"));
    assert_eq!(fs::read_to_string(retained.join("ores")).unwrap(), original);
    assert!(!f.root.join("args").exists(), "no build command may run");
}

#[test]
fn symlinked_classpath_does_not_overwrite_external_file() {
    let f = Fixture::new();
    let outside = f.root.join("classpath-sentinel");
    fs::write(&outside, "retain this file").unwrap();
    symlink(&outside, f.root.join(".work/classpath.txt")).unwrap();
    let output = f.run_setup(false);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("classpath path must not be a symlink"));
    assert_eq!(fs::read_to_string(&outside).unwrap(), "retain this file");
    assert!(!f.root.join("args").exists(), "Maven must not run");
    assert!(!f.launcher.exists(), "old launcher must be invalidated");
}

#[test]
fn symlinked_compiler_target_does_not_run_maven_clean() {
    let f = Fixture::new();
    let outside = f.root.join("target-sentinel");
    fs::create_dir(&outside).unwrap();
    fs::write(outside.join("keep.txt"), "keep").unwrap();
    symlink(&outside, f.compiler.join("target")).unwrap();
    let output = f.run_setup(false);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("target directory must not be a symlink"));
    assert_eq!(fs::read_to_string(outside.join("keep.txt")).unwrap(), "keep");
    assert!(!f.root.join("args").exists(), "Maven clean must not run");
    assert!(!f.launcher.exists(), "old launcher must be invalidated");
}

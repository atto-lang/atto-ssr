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
            r#"#!/bin/sh
printf '%s\n' "$@" > "$SETUP_ARGS"
exitcode="${SETUP_FAIL:-0}"
if [ "$exitcode" != "0" ]; then exit "$exitcode"; fi
case "${SETUP_OUTPUTS:-all}" in
  all|classes) mkdir -p "$SETUP_CLASS_DIR"; printf 'fixture' > "$SETUP_CLASS_DIR/OresMain.class" ;;
esac
case "${SETUP_OUTPUTS:-all}" in
  all|classpath) printf 'stub-dependency.jar\n' > "$SETUP_CLASSPATH" ;;
esac
exit 0
"#,
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
        self.run_setup_with_offline(fail, None)
    }

    fn run_setup_with_offline(&self, fail: bool, offline: Option<&str>) -> Output {
        self.run_setup_with_outputs(fail, offline, "all")
    }

    fn run_setup_with_outputs(&self, fail: bool, offline: Option<&str>, outputs: &str) -> Output {
        let old_path = env::var("PATH").unwrap_or_default();
        let mut command = Command::new("bash");
        command
            .arg("scripts/setup.sh")
            .current_dir(&self.root)
            .env("PATH", format!("{}:{old_path}", self.bin.display()))
            .env("SETUP_ARGS", self.root.join("args"))
            .env("SETUP_FAIL", if fail { "1" } else { "0" })
            .env("SETUP_CLASS_DIR", self.compiler.join("target/classes/dev/oreslang/launcher"))
            .env("SETUP_CLASSPATH", self.root.join(".work/classpath.txt"))
            .env("SETUP_OUTPUTS", outputs)
            .env_remove("ORESLANG_OFFLINE");
        if let Some(value) = offline {
            command.env("ORESLANG_OFFLINE", value);
        }
        command.output().unwrap()
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

#[test]
fn offline_prepopulated_exact_tree_builds_without_origin_clone() {
    let f = Fixture::new();
    let result = f.run_setup_with_offline(false, Some("1"));
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    let out = String::from_utf8_lossy(&result.stdout);
    assert!(out.contains("compiler snapshot: pinned_ref="));
    assert!(out.contains(&format!("tree={}", f.git(&["rev-parse", "HEAD^{tree}"]))));
    assert!(f.launcher.exists());
}

#[test]
fn offline_missing_compiler_fails_closed_before_maven() {
    let f = Fixture::new();
    fs::remove_dir_all(&f.compiler).unwrap();
    let result = f.run_setup_with_offline(false, Some("1"));
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("offline compiler checkout missing"));
    assert!(!f.launcher.exists());
    assert!(!f.root.join("args").exists(), "Maven must not run");
}

#[test]
fn invalid_offline_setting_fails_closed_before_maven() {
    let f = Fixture::new();
    let result = f.run_setup_with_offline(false, Some("unexpected"));
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("ORESLANG_OFFLINE must be 0 or 1"));
    assert!(!f.launcher.exists());
    assert!(!f.root.join("args").exists(), "Maven must not run");
}

#[test]
fn same_tree_mirror_commit_is_accepted_with_provenance() {
    let f = Fixture::new();
    let source_commit = f.git(&["rev-parse", "HEAD"]);
    f.git(&[
        "-c", "user.name=Fixture",
        "-c", "user.email=fixture@example.invalid",
        "commit", "--allow-empty", "-qm", "different commit, identical Git tree",
    ]);
    let copied_commit = f.git(&["rev-parse", "HEAD"]);
    assert_ne!(copied_commit, source_commit);
    let result = f.run_setup_with_offline(false, Some("1"));
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    let out = String::from_utf8_lossy(&result.stdout);
    assert!(out.contains(&format!("pinned_ref={source_commit}")));
    assert!(out.contains(&format!("checkout_ref={copied_commit}")));
    assert!(f.launcher.exists());
}

#[test]
fn clean_but_different_tree_is_rejected_before_build() {
    let f = Fixture::new();
    fs::write(f.compiler.join("pom.xml"), "<project changed='true'/>").unwrap();
    f.git(&["add", "pom.xml"]);
    f.git(&[
        "-c", "user.name=Fixture",
        "-c", "user.email=fixture@example.invalid",
        "commit", "-qm", "different Git tree",
    ]);
    let result = f.run_setup_with_offline(false, Some("1"));
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("compiler source tree does not match"));
    assert!(!f.launcher.exists());
    assert!(!f.root.join("args").exists(), "Maven must not run");
}

#[test]
fn offline_mode_forces_maven_offline_resolution() {
    let f = Fixture::new();
    let result = f.run_setup_with_offline(false, Some("1"));
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    let args = fs::read_to_string(f.root.join("args")).unwrap();
    assert!(args.lines().any(|arg| arg == "-o"), "Maven must not resolve from network");
    assert!(f.launcher.exists());
}

#[test]
fn default_mode_preserves_online_maven_resolution() {
    let f = Fixture::new();
    let result = f.run_setup(false);
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    let args = fs::read_to_string(f.root.join("args")).unwrap();
    assert!(!args.lines().any(|arg| arg == "-o"), "default mode must preserve Maven behavior");
}

#[test]
fn zero_exit_maven_without_artifacts_does_not_publish_launcher() {
    let f = Fixture::new();
    let output = f.run_setup_with_outputs(false, Some("1"), "none");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("classpath"));
    assert!(!f.launcher.exists());
}

#[test]
fn zero_exit_maven_without_main_class_does_not_publish_launcher() {
    let f = Fixture::new();
    let output = f.run_setup_with_outputs(false, Some("1"), "classpath");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("OresMain"));
    assert!(!f.launcher.exists());
}

#[test]
fn zero_exit_maven_without_classpath_does_not_publish_launcher() {
    let f = Fixture::new();
    let output = f.run_setup_with_outputs(false, Some("1"), "classes");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("classpath"));
    assert!(!f.launcher.exists());
}

#[test]
fn stale_ignored_classpath_and_entrypoint_do_not_validate_maven_success() {
    let f = Fixture::new();
    // Real Maven compiler checkouts ignore target/; reproduce that instead
    // of allowing the Git dirty-tree gate to mask the stale artifact defect.
    fs::write(f.compiler.join(".git/info/exclude"), "target/\n").unwrap();
    let entry = f.compiler.join("target/classes/dev/oreslang/launcher/OresMain.class");
    fs::create_dir_all(entry.parent().unwrap()).unwrap();
    fs::write(&entry, "stale bytecode").unwrap();
    let classpath = f.root.join(".work/classpath.txt");
    fs::write(&classpath, "stale-dependencies.jar\n").unwrap();

    let output = f.run_setup_with_outputs(false, Some("1"), "none");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("classpath"));
    assert!(!f.launcher.exists());
    assert!(!entry.exists(), "stale entrypoint must be invalidated before Maven");
    assert!(!classpath.exists(), "stale classpath must be invalidated before Maven");
    assert!(f.root.join("args").exists(), "the Maven mock must actually execute");
}

#[test]
fn symlinked_nested_class_directory_is_rejected_before_maven() {
    let f = Fixture::new();
    fs::write(f.compiler.join(".git/info/exclude"), "target/\n").unwrap();
    let external = f.root.join("outside-classes");
    fs::create_dir_all(&external).unwrap();
    fs::write(external.join("sentinel"), "preserved").unwrap();
    fs::create_dir_all(f.compiler.join("target")).unwrap();
    symlink(&external, f.compiler.join("target/classes")).unwrap();

    let output = f.run_setup_with_outputs(false, Some("1"), "all");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("class-output directory must not be a symlink"));
    assert_eq!(fs::read_to_string(external.join("sentinel")).unwrap(), "preserved");
    assert!(!f.root.join("args").exists(), "must fail before Maven clean");
    assert!(!f.launcher.exists());
}

#[test]
fn symlinked_entrypoint_is_rejected_without_touching_external_target() {
    let f = Fixture::new();
    fs::write(f.compiler.join(".git/info/exclude"), "target/\n").unwrap();
    let external = f.root.join("outside-bytecode");
    fs::write(&external, "preserved").unwrap();
    let entry = f.compiler.join("target/classes/dev/oreslang/launcher/OresMain.class");
    fs::create_dir_all(entry.parent().unwrap()).unwrap();
    symlink(&external, &entry).unwrap();

    let output = f.run_setup_with_outputs(false, Some("1"), "all");
    assert_eq!(output.status.code(), Some(65));
    assert!(String::from_utf8_lossy(&output.stderr).contains("compiler entrypoint must not be a symlink"));
    assert_eq!(fs::read_to_string(&external).unwrap(), "preserved");
    assert!(!f.root.join("args").exists(), "must fail before Maven clean");
    assert!(!f.launcher.exists());
}

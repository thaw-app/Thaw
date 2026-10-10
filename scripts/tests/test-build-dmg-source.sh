#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# macOS ships Ruby's YAML reader; execute the actual action scripts, not copies.
/usr/bin/ruby -ryaml - "$ROOT" "$TEMP_DIR" <<'RUBY'
root, temp = ARGV
action = YAML.load_file("#{root}/.github/actions/checkout-source/action.yml")
workflow = YAML.load_file("#{root}/.github/workflows/build-dmg.yml")
job = workflow.fetch("jobs").fetch("build-dmg")
steps = job.fetch("steps")
source = steps.find { |step| step["id"] == "source" }.fetch("with")
checkout = action.fetch("runs").fetch("steps").find { |step| step["uses"] }.fetch("with")

raise "Root checkout compatibility lost" unless action.dig("inputs", "path", "default") == "."
raise "Checkout ignores path" unless checkout["path"] == '${{ inputs.path }}'
raise "Source ref no longer defaults to dispatch SHA" unless checkout["ref"] == '${{ inputs.ref || github.sha }}'
raise "Wrong source path" unless source["path"] == "Thaw"
raise "Source ref not forwarded" unless source["ref"] == '${{ inputs.ref }}'
raise "Credentials persisted" unless checkout["persist-credentials"] == false &&
  steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }
       .all? { |step| step.dig("with", "persist-credentials") == false }
upload = steps.find { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }.fetch("with")
raise "Upload must contain only the DMG" unless upload["path"] == 'build/${{ env.DMG_NAME }}'

scripts = {
  "metadata" => action["runs"]["steps"].find { |step| step["id"] == "meta" },
  "preserve" => action["runs"]["steps"].find { |step| step["name"] == "Set build actions aside" },
  "restore" => action["runs"]["steps"].find { |step| step["name"] == "Restore build actions" }
}
raise "Metadata ignores path" unless scripts["metadata"].dig("env", "SOURCE_PATH") == '${{ inputs.path }}'
scripts.each { |name, step| File.write("#{temp}/#{name}.sh", step.fetch("run")) }
RUBY

mkdir -p "$TEMP_DIR/bin"
cat > "$TEMP_DIR/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 4 && "$1" == -C && "$3" == rev-parse && "$4" == HEAD ]]
IFS= read -r commit < "$2/.fixture-commit"
printf '%s\n' "$commit"
SH
chmod +x "$TEMP_DIR/bin/git"

cat > "$TEMP_DIR/project.pbxproj" <<'PLIST'
{
    objects = {
        HELPER = { isa = PBXNativeTarget; name = Helper; buildConfigurationList = HELPER_CONFIGS; };
        HELPER_CONFIGS = { buildConfigurations = (HELPER_RELEASE); };
        HELPER_RELEASE = { name = Release; buildSettings = { MACOSX_DEPLOYMENT_TARGET = 25.0; }; };
        APP = { isa = PBXNativeTarget; name = Thaw; buildConfigurationList = APP_CONFIGS; };
        APP_CONFIGS = { buildConfigurations = (DEBUG, RELEASE); };
        DEBUG = { name = Debug; buildSettings = { MACOSX_DEPLOYMENT_TARGET = 99.0; }; };
        RELEASE = { name = Release; buildSettings = { MACOSX_DEPLOYMENT_TARGET = 27.4; }; };
    };
}
PLIST

check_metadata() {
    local source_path="$1" project_name="$2" workspace commit
    workspace=$(mktemp -d "$TEMP_DIR/workspace with spaces.XXXXXX")
    commit=$(printf '%s' "$source_path" | shasum | cut -d ' ' -f 1)
    mkdir -p "$workspace/$source_path/Thaw.xcodeproj" "$workspace/tmp"
    cp "$TEMP_DIR/project.pbxproj" "$workspace/$source_path/Thaw.xcodeproj/project.pbxproj"
    printf '%s\n' "$commit" > "$workspace/$source_path/.fixture-commit"
    (
        cd "$workspace"
        PATH="$TEMP_DIR/bin:$PATH" SOURCE_PATH="$source_path" RUNNER_TEMP="$workspace/tmp" \
            GITHUB_OUTPUT="$workspace/output" GITHUB_REPOSITORY=thaw-app/Thaw \
            bash "$TEMP_DIR/metadata.sh" > "$workspace/log"
    )
    printf 'commit=%s\nproject_name=%s\ndeployment_target=27.4\n' "$commit" "$project_name" \
        > "$workspace/expected"
    cmp "$workspace/expected" "$workspace/output"
}

check_metadata . Thaw.xcodeproj
check_metadata Thaw Thaw/Thaw.xcodeproj
check_metadata 'checkout with spaces/' 'checkout with spaces/Thaw.xcodeproj'
printf 'PASS: root, nested, and spaced checkout paths select the app Release settings and source commit\n'

mkdir -p "$TEMP_DIR/missing/tmp"
if (
    cd "$TEMP_DIR/missing"
    SOURCE_PATH=Thaw RUNNER_TEMP="$TEMP_DIR/missing/tmp" \
        GITHUB_OUTPUT="$TEMP_DIR/missing/output" GITHUB_REPOSITORY=thaw-app/Thaw \
        bash "$TEMP_DIR/metadata.sh" > "$TEMP_DIR/missing/log" 2>&1
); then
    printf 'Missing project unexpectedly succeeded\n' >&2
    exit 1
fi
[[ ! -s "$TEMP_DIR/missing/output" ]]
printf 'PASS: a missing source project fails without emitting build settings\n'

export ACTION_PATH="$TEMP_DIR/actions fixture/.github/actions/checkout-source"
export RUNNER_TEMP="$TEMP_DIR/runner temp"
mkdir -p "$ACTION_PATH" "$RUNNER_TEMP" "$(dirname "$ACTION_PATH")/other"
cp "$ROOT/.github/actions/checkout-source/action.yml" "$ACTION_PATH/action.yml"
printf 'another action\n' > "$(dirname "$ACTION_PATH")/other/action.yml"
bash "$TEMP_DIR/preserve.sh"
rm -rf "$(dirname "$ACTION_PATH")"
bash "$TEMP_DIR/restore.sh"
cmp "$ROOT/.github/actions/checkout-source/action.yml" "$ACTION_PATH/action.yml"
grep -Fxq 'another action' "$(dirname "$ACTION_PATH")/other/action.yml"
printf 'PASS: all bootstrap actions survive checking out an older source ref\n'

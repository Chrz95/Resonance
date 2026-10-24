"""Runner patch checks; native Windows compilation is covered by the build job."""
import importlib.util
from pathlib import Path

import pytest


spec = importlib.util.spec_from_file_location(
    "windows_session", Path(__file__).resolve().parents[1] / "windows_session.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

TEMPLATE = '''#include "flutter_window.h"
bool FlutterWindow::OnCreate() {
  RegisterPlugins(flutter_controller_->engine());
  return true;
}
void FlutterWindow::OnDestroy() {
  flutter_controller_ = nullptr;
}
LRESULT FlutterWindow::MessageHandler(UINT message) {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  return 0;
}
'''


@pytest.fixture
def client(tmp_path):
    runner = tmp_path / "windows" / "runner"
    runner.mkdir(parents=True)
    (runner / "flutter_window.cpp").write_text(TEMPLATE)
    config = tmp_path / "platform_config" / "windows"
    config.mkdir(parents=True)
    (config / "session_close.h").write_text("// session close header")
    return tmp_path


def test_checkpoint_precedes_flutter_message_dispatch(client):
    module.install_windows_session(client)
    code = (client / "windows" / "runner" / "flutter_window.cpp").read_text()
    assert code.index("resonance_session::Handle(message)") < code.index("// Give Flutter")
    assert code.index("RegisterPlugins(") < code.index("resonance_session::Initialize(")
    assert code.index("resonance_session::Dispose();") < code.index("flutter_controller_ = nullptr")


def test_repeat_bootstrap_does_not_duplicate_hooks_and_refreshes_header(client):
    module.install_windows_session(client)
    runner = client / "windows" / "runner"
    initial = (runner / "flutter_window.cpp").read_text()
    (client / "platform_config" / "windows" / "session_close.h").write_text("// updated")
    module.install_windows_session(client)
    assert (runner / "flutter_window.cpp").read_text() == initial
    assert (runner / "session_close.h").read_text() == "// updated"


def test_unknown_template_preserves_runner(client):
    runner = client / "windows" / "runner" / "flutter_window.cpp"
    changed = TEMPLATE.replace("  RegisterPlugins(", "  DifferentPlugins(")
    runner.write_text(changed)
    with pytest.raises(RuntimeError, match="template changed"):
        module.install_windows_session(client)
    assert runner.read_text() == changed

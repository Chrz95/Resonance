"""Install a small session-close handshake in the SDK-generated Windows runner."""
from pathlib import Path
import shutil


def install_windows_session(client: Path):
    runner = client / "windows" / "runner"
    file = runner / "flutter_window.cpp"
    code = file.read_text()
    marker = "// RESONANCE SESSION CLOSE"
    shutil.copyfile(client / "platform_config" / "windows" / "session_close.h", runner / "session_close.h")
    if marker in code:
        return
    anchors = [
        '#include "flutter_window.h"',
        '  RegisterPlugins(flutter_controller_->engine());',
        'void FlutterWindow::OnDestroy() {',
        '  // Give Flutter, including plugins, an opportunity to handle window messages.',
    ]
    for anchor in anchors:
        if code.count(anchor) != 1:
            raise RuntimeError("Windows runner template changed. Cannot install session-close checkpoint safely.")
    code = code.replace(anchors[0], anchors[0] + '\n#include "session_close.h"\n' + marker)
    code = code.replace(anchors[1], anchors[1] + '\n  resonance_session::Initialize(flutter_controller_->engine()->messenger(), GetHandle());')
    code = code.replace(anchors[2], anchors[2] + '\n  resonance_session::Dispose();')
    code = code.replace(anchors[3], '  if (resonance_session::Handle(message)) return 0;\n' + anchors[3])
    file.write_text(code)

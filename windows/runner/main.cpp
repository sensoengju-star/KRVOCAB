// Winsock must be included before windows.h, which would otherwise pull in the
// older winsock.h and collide with it.
#include <winsock2.h>
#pragma comment(lib, "ws2_32.lib")

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The port the running app listens on for "show yourself" — see
// lib/services/single_instance.dart. The two must stay in step.
constexpr u_short kSingleInstancePort = 45731;

// Asks the copy that is already running to bring its window to the front.
//
// A bare connection is the whole message: the Dart side treats any connection
// as a request to show. A refused connection returns at once, so this can
// never hang the launch.
bool PokeRunningInstance() {
  WSADATA wsa;
  if (::WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return false;
  bool answered = false;
  SOCKET s = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s != INVALID_SOCKET) {
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = ::htons(kSingleInstancePort);
    addr.sin_addr.s_addr = ::htonl(INADDR_LOOPBACK);
    answered =
        ::connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0;
    ::closesocket(s);
  }
  ::WSACleanup();
  return answered;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance, decided before Flutter starts.
  //
  // Maldari lives in the tray, so its window is usually hidden and has no
  // taskbar button to restore. Clicking the pinned icon therefore launches a
  // whole new process — and when this check lived only in Dart, that process
  // had to boot the engine, the VM and a window before it could even learn it
  // was redundant. That wasted launch is why opening from the taskbar felt
  // slower than opening from the tray. A named mutex answers the question in
  // microseconds, so the second copy hands over and leaves before any of that.
  //
  // The handle is deliberately never closed: the OS releases it when this
  // process ends, however it ends, so it cannot go stale the way a lock file
  // can after a hard kill.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\Maldari.SingleInstance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    PokeRunningInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"maldari", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

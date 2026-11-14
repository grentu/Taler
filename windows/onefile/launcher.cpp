// Taler single-file launcher for Windows.
//
// The Flutter release folder (taler.exe, DLLs, data\) is appended to this
// executable as a simple archive. On start the launcher unpacks it once into
// %LOCALAPPDATA%\Taler\app-<build id> and starts taler.exe from there, so the
// user only ever downloads and runs one file.
//
// Archive layout (little-endian), placed right after the PE image:
//   entries: uint32 pathBytes | UTF-8 relative path ('/' separators) | uint64 size | data
//   footer (32 bytes): "TALERPK1" | uint64 archiveOffset | uint64 entryCount | uint64 buildId
// The archive is written by scripts/pack_onefile.ps1.

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <knownfolders.h>

#include <cstdint>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>

namespace {

constexpr char kMagic[8] = {'T', 'A', 'L', 'E', 'R', 'P', 'K', '1'};
constexpr wchar_t kAppExe[] = L"taler.exe";
constexpr wchar_t kMarker[] = L".taler-extracted";

struct Footer {
  char magic[8];
  uint64_t archive_offset;
  uint64_t entry_count;
  uint64_t build_id;
};
static_assert(sizeof(Footer) == 32, "footer must be 32 bytes");

bool g_silent = false;

void ShowError(const std::wstring& message) {
  if (g_silent) {
    OutputDebugStringW(message.c_str());
    return;
  }
  MessageBoxW(nullptr, message.c_str(), L"Taler", MB_OK | MB_ICONERROR);
}

std::wstring LastErrorText() {
  wchar_t buffer[512] = {0};
  FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                 nullptr, GetLastError(), 0, buffer, 511, nullptr);
  return buffer;
}

bool ReadExact(HANDLE file, void* data, DWORD size) {
  auto* out = static_cast<uint8_t*>(data);
  while (size > 0) {
    DWORD read = 0;
    if (!ReadFile(file, out, size, &read, nullptr) || read == 0) return false;
    out += read;
    size -= read;
  }
  return true;
}

bool WriteExact(HANDLE file, const void* data, DWORD size) {
  const auto* in = static_cast<const uint8_t*>(data);
  while (size > 0) {
    DWORD written = 0;
    if (!WriteFile(file, in, size, &written, nullptr) || written == 0) return false;
    in += written;
    size -= written;
  }
  return true;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int len = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), len);
  return out;
}

bool CreateDirs(const std::wstring& dir) {
  const int rc = SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
  return rc == ERROR_SUCCESS || rc == ERROR_ALREADY_EXISTS ||
         rc == ERROR_FILE_EXISTS;
}

bool FileExists(const std::wstring& path) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring LocalAppData() {
  PWSTR raw = nullptr;
  std::wstring result;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &raw)) &&
      raw != nullptr) {
    result = raw;
  }
  if (raw != nullptr) CoTaskMemFree(raw);
  if (result.empty()) {
    wchar_t temp[MAX_PATH + 1] = {0};
    GetTempPathW(MAX_PATH, temp);
    result = temp;
  }
  while (!result.empty() && (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

std::wstring Hex64(uint64_t value) {
  wchar_t buf[17] = {0};
  swprintf_s(buf, L"%016llx", static_cast<unsigned long long>(value));
  return buf;
}

// Removes app-* folders left by previous builds. Best effort: a folder that is
// still in use stays until the next launch.
void RemoveOldVersions(const std::wstring& root, const std::wstring& keep) {
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW((root + L"\\app-*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return;
  do {
    if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    const std::wstring name = data.cFileName;
    if (name == keep) continue;
    std::wstring from = root + L"\\" + name;
    from.push_back(L'\0');  // SHFileOperation wants a double-null-terminated list.
    SHFILEOPSTRUCTW op = {};
    op.wFunc = FO_DELETE;
    op.pFrom = from.c_str();
    op.fFlags = FOF_NO_UI;
    SHFileOperationW(&op);
  } while (FindNextFileW(find, &data));
  FindClose(find);
}

bool Extract(HANDLE self, const Footer& footer, const std::wstring& target,
             std::wstring* error) {
  LARGE_INTEGER pos;
  pos.QuadPart = static_cast<LONGLONG>(footer.archive_offset);
  if (!SetFilePointerEx(self, pos, nullptr, FILE_BEGIN)) {
    *error = L"seek: " + LastErrorText();
    return false;
  }
  if (!CreateDirs(target)) {
    *error = L"Не удалось создать папку " + target;
    return false;
  }

  std::vector<uint8_t> buffer(1 << 20);
  for (uint64_t i = 0; i < footer.entry_count; ++i) {
    uint32_t path_len = 0;
    if (!ReadExact(self, &path_len, sizeof(path_len)) || path_len == 0 ||
        path_len > 4096) {
      *error = L"Повреждённый архив: путь";
      return false;
    }
    std::string path_utf8(path_len, '\0');
    if (!ReadExact(self, path_utf8.data(), path_len)) {
      *error = L"Повреждённый архив: имя файла";
      return false;
    }
    uint64_t size = 0;
    if (!ReadExact(self, &size, sizeof(size))) {
      *error = L"Повреждённый архив: размер";
      return false;
    }

    std::wstring rel = Utf8ToWide(path_utf8);
    if (rel.empty() || rel.find(L"..") != std::wstring::npos ||
        rel.find(L':') != std::wstring::npos || rel[0] == L'/' ||
        rel[0] == L'\\') {
      *error = L"Недопустимый путь в архиве";
      return false;
    }
    for (auto& ch : rel) {
      if (ch == L'/') ch = L'\\';
    }
    const std::wstring full = target + L"\\" + rel;
    const size_t slash = full.find_last_of(L'\\');
    if (slash != std::wstring::npos && !CreateDirs(full.substr(0, slash))) {
      *error = L"Не удалось создать папку для " + rel;
      return false;
    }

    HANDLE out = CreateFileW(full.c_str(), GENERIC_WRITE, 0, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) {
      *error = L"Не удалось записать " + rel + L": " + LastErrorText();
      return false;
    }
    uint64_t left = size;
    bool ok = true;
    while (left > 0) {
      const DWORD chunk = static_cast<DWORD>(
          left < buffer.size() ? left : static_cast<uint64_t>(buffer.size()));
      if (!ReadExact(self, buffer.data(), chunk) ||
          !WriteExact(out, buffer.data(), chunk)) {
        ok = false;
        break;
      }
      left -= chunk;
    }
    CloseHandle(out);
    if (!ok) {
      *error = L"Ошибка распаковки " + rel;
      return false;
    }
  }

  HANDLE marker = CreateFileW((target + L"\\" + kMarker).c_str(), GENERIC_WRITE,
                              0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN,
                              nullptr);
  if (marker != INVALID_HANDLE_VALUE) CloseHandle(marker);
  return true;
}

// Everything after the program name, with the original quoting kept.
std::wstring ArgsAfterProgramName() {
  const wchar_t* cmd = GetCommandLineW();
  bool quoted = false;
  while (*cmd) {
    if (*cmd == L'"') {
      quoted = !quoted;
    } else if (!quoted && (*cmd == L' ' || *cmd == L'\t')) {
      break;
    }
    ++cmd;
  }
  while (*cmd == L' ' || *cmd == L'\t') ++cmd;
  return cmd;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  bool extract_only = false;
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  for (int i = 1; argv != nullptr && i < argc; ++i) {
    if (wcscmp(argv[i], L"--taler-extract-only") == 0) extract_only = true;
  }
  if (argv != nullptr) LocalFree(argv);
  g_silent = extract_only;

  std::vector<wchar_t> self_path(32768, L'\0');
  const DWORD n = GetModuleFileNameW(nullptr, self_path.data(),
                                     static_cast<DWORD>(self_path.size()));
  if (n == 0 || n >= self_path.size()) {
    ShowError(L"Не удалось определить путь к Taler");
    return 1;
  }

  HANDLE self = CreateFileW(self_path.data(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (self == INVALID_HANDLE_VALUE) {
    ShowError(L"Не удалось открыть файл Taler: " + LastErrorText());
    return 1;
  }

  LARGE_INTEGER file_size;
  Footer footer = {};
  bool valid = GetFileSizeEx(self, &file_size) &&
               file_size.QuadPart > static_cast<LONGLONG>(sizeof(Footer));
  if (valid) {
    LARGE_INTEGER pos;
    pos.QuadPart = file_size.QuadPart - static_cast<LONGLONG>(sizeof(Footer));
    valid = SetFilePointerEx(self, pos, nullptr, FILE_BEGIN) &&
            ReadExact(self, &footer, sizeof(Footer)) &&
            std::memcmp(footer.magic, kMagic, sizeof(kMagic)) == 0 &&
            footer.archive_offset <
                static_cast<uint64_t>(file_size.QuadPart);
  }
  if (!valid) {
    CloseHandle(self);
    ShowError(L"Файл Taler повреждён. Скачайте его заново.");
    return 1;
  }

  const std::wstring root = LocalAppData() + L"\\Taler";
  const std::wstring folder = L"app-" + Hex64(footer.build_id);
  const std::wstring target = root + L"\\" + folder;
  const std::wstring app_exe = target + L"\\" + kAppExe;

  if (!FileExists(target + L"\\" + kMarker) || !FileExists(app_exe)) {
    // One extraction at a time if the user double-clicks twice.
    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\TalerOneFileExtract");
    if (mutex != nullptr) WaitForSingleObject(mutex, 120000);
    std::wstring error;
    bool ok = true;
    if (!FileExists(target + L"\\" + kMarker) || !FileExists(app_exe)) {
      ok = Extract(self, footer, target, &error);
      if (ok) RemoveOldVersions(root, folder);
    }
    if (mutex != nullptr) {
      ReleaseMutex(mutex);
      CloseHandle(mutex);
    }
    if (!ok) {
      CloseHandle(self);
      ShowError(L"Не удалось подготовить Taler к запуску.\n\n" + error);
      return 1;
    }
  }
  CloseHandle(self);

  if (extract_only) return 0;

  std::wstring command = L"\"" + app_exe + L"\"";
  const std::wstring args = ArgsAfterProgramName();
  if (!args.empty()) command += L" " + args;
  std::vector<wchar_t> mutable_cmd(command.begin(), command.end());
  mutable_cmd.push_back(L'\0');

  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};
  if (!CreateProcessW(app_exe.c_str(), mutable_cmd.data(), nullptr, nullptr,
                      FALSE, 0, nullptr, target.c_str(), &si, &pi)) {
    ShowError(L"Не удалось запустить Taler: " + LastErrorText());
    return 1;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 0;
}

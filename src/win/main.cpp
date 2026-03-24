#ifdef _WIN32

#include <algorithm>
#include <commdlg.h>
#include <shellapi.h>
#include <string>
#include <vector>

#include <windows.h>

// Keep the first Windows shell minimal: create a native window, optionally
// open a PDF from the command line, and report the current status in the view.

#include "core/document.h"

namespace {

const wchar_t kWindowClassName[] = L"pdfview_main_window";
const UINT_PTR kCommandOpen = 1001;
const UINT_PTR kCommandExit = 1002;

struct AppState {
  std::wstring status_line;
  std::wstring detail_line;
  pdfview::core::DocumentPtr document;
  pdfview::core::Bitmap page_bitmap;
  RECT page_rect{};
};

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int size =
      MultiByteToWideChar(CP_UTF8,
                          0,
                          value.c_str(),
                          static_cast<int>(value.size()),
                          NULL,
                          0);
  if (size <= 0) {
    return L"";
  }

  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8,
                      0,
                      value.c_str(),
                      static_cast<int>(value.size()),
                      &wide[0],
                      size);
  return wide;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }

  const int size =
      WideCharToMultiByte(CP_UTF8,
                          0,
                          value.c_str(),
                          static_cast<int>(value.size()),
                          NULL,
                          0,
                          NULL,
                          NULL);
  if (size <= 0) {
    return "";
  }

  std::string utf8(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8,
                      0,
                      value.c_str(),
                      static_cast<int>(value.size()),
                      &utf8[0],
                      size,
                      NULL,
                      NULL);
  return utf8;
}

std::wstring BaseName(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

std::wstring BuildWindowTitle(const AppState* state) {
  if (state != NULL && state->document) {
    return L"pdfview - " + state->detail_line;
  }
  return L"pdfview";
}

void ResetToEmptyState(AppState* state) {
  if (state == NULL) {
    return;
  }

  state->document.reset();
  state->page_bitmap = pdfview::core::Bitmap();
  state->page_rect = RECT();
  state->status_line = L"Open a PDF to begin";
  state->detail_line =
      L"This Windows shell currently verifies window creation, opening, and first-page rendering.";
}

float ComputeFitScaleForFirstPage(const RECT& client_rect,
                                  const pdfview::core::PageSize& page_size) {
  const float available_width =
      static_cast<float>(std::max((client_rect.right - client_rect.left) - 48, 120L));
  const float available_height =
      static_cast<float>(std::max((client_rect.bottom - client_rect.top) - 120, 120L));
  if (page_size.width <= 0.0f || page_size.height <= 0.0f) {
    return 1.0f;
  }

  const float scale_x = available_width / page_size.width;
  const float scale_y = available_height / page_size.height;
  return std::max(0.1f, std::min(scale_x, scale_y));
}

void UpdatePageRect(const RECT& client_rect,
                    const pdfview::core::Bitmap& bitmap,
                    RECT* page_rect) {
  if (page_rect == NULL) {
    return;
  }

  const int width = bitmap.width;
  const int height = bitmap.height;
  const int content_width = client_rect.right - client_rect.left;
  page_rect->left = std::max((content_width - width) / 2, 24);
  page_rect->top = 96;
  page_rect->right = page_rect->left + width;
  page_rect->bottom = page_rect->top + height;
}

void RenderFirstPageToClient(HWND window, AppState* state) {
  if (window == NULL || state == NULL || !state->document || state->document->page_count() <= 0) {
    return;
  }

  RECT client_rect{};
  GetClientRect(window, &client_rect);
  const pdfview::core::PageSize page_size = state->document->page_size(0);
  const float render_scale = ComputeFitScaleForFirstPage(client_rect, page_size);
  const pdfview::core::RenderPageResult render_result =
      state->document->render_page(0, render_scale);

  if (!render_result.ok()) {
    state->page_bitmap = pdfview::core::Bitmap();
    state->status_line = L"Failed to render first page";
    state->detail_line = Utf8ToWide(render_result.error);
    return;
  }

  state->page_bitmap = render_result.bitmap;
  UpdatePageRect(client_rect, state->page_bitmap, &state->page_rect);
  state->status_line = L"PDF loaded";
}

bool OpenDocumentPath(HWND window, const std::wstring& path, AppState* state) {
  if (state == NULL) {
    return false;
  }

  if (path.empty()) {
    return false;
  }

  const std::string utf8_path = WideToUtf8(path);
  const pdfview::core::OpenDocumentResult open_result =
      pdfview::core::open_document(utf8_path);
  if (!open_result.ok()) {
    state->document.reset();
    state->page_bitmap = pdfview::core::Bitmap();
    state->status_line = L"Failed to open PDF";
    state->detail_line = Utf8ToWide(open_result.error);
    if (window != NULL) {
      MessageBoxW(window, state->detail_line.c_str(), L"pdfview", MB_OK | MB_ICONERROR);
      SetWindowTextW(window, BuildWindowTitle(state).c_str());
      InvalidateRect(window, NULL, TRUE);
    }
    return false;
  }

  state->document = open_result.document;
  state->status_line = L"PDF loaded";
  state->detail_line =
      BaseName(path) + L" (" + std::to_wstring(state->document->page_count()) + L" pages)";
  if (window != NULL) {
    RenderFirstPageToClient(window, state);
    SetWindowTextW(window, BuildWindowTitle(state).c_str());
    InvalidateRect(window, NULL, TRUE);
  }
  return true;
}

bool ShowOpenDialogAndLoad(HWND window, AppState* state) {
  wchar_t path_buffer[MAX_PATH] = L"";
  OPENFILENAMEW dialog{};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = window;
  dialog.lpstrFilter =
      L"PDF Files (*.pdf)\0*.pdf\0All Files (*.*)\0*.*\0";
  dialog.lpstrFile = path_buffer;
  dialog.nMaxFile = MAX_PATH;
  dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
  dialog.lpstrDefExt = L"pdf";

  if (!GetOpenFileNameW(&dialog)) {
    return false;
  }

  return OpenDocumentPath(window, path_buffer, state);
}

HMENU BuildMainMenu() {
  HMENU main_menu = CreateMenu();
  HMENU file_menu = CreatePopupMenu();
  AppendMenuW(file_menu, MF_STRING, kCommandOpen, L"&Open...\tCtrl+O");
  AppendMenuW(file_menu, MF_SEPARATOR, 0, NULL);
  AppendMenuW(file_menu, MF_STRING, kCommandExit, L"E&xit");
  AppendMenuW(main_menu, MF_POPUP, reinterpret_cast<UINT_PTR>(file_menu), L"&File");
  return main_menu;
}

void DrawPageBitmap(HDC dc, const AppState* state) {
  if (state == NULL || state->page_bitmap.pixels.empty()) {
    return;
  }

  RECT page_rect = state->page_rect;
  HBRUSH shadow_brush = CreateSolidBrush(RGB(210, 210, 210));
  RECT shadow_rect = page_rect;
  OffsetRect(&shadow_rect, 4, 4);
  FillRect(dc, &shadow_rect, shadow_brush);
  DeleteObject(shadow_brush);

  HBRUSH page_brush = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(dc, &page_rect, page_brush);
  FrameRect(dc, &page_rect, reinterpret_cast<HBRUSH>(GetStockObject(LTGRAY_BRUSH)));
  DeleteObject(page_brush);

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = state->page_bitmap.width;
  bitmap_info.bmiHeader.biHeight = -state->page_bitmap.height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  StretchDIBits(dc,
                page_rect.left,
                page_rect.top,
                page_rect.right - page_rect.left,
                page_rect.bottom - page_rect.top,
                0,
                0,
                state->page_bitmap.width,
                state->page_bitmap.height,
                state->page_bitmap.pixels.data(),
                &bitmap_info,
                DIB_RGB_COLORS,
                SRCCOPY);
}

void PaintWindow(HWND window, const AppState* state) {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window, &paint);

  RECT client_rect{};
  GetClientRect(window, &client_rect);
  FillRect(dc, &client_rect, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(32, 32, 32));

  HFONT title_font = CreateFontW(24,
                                 0,
                                 0,
                                 0,
                                 FW_SEMIBOLD,
                                 FALSE,
                                 FALSE,
                                 FALSE,
                                 DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS,
                                 CLIP_DEFAULT_PRECIS,
                                 CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH | FF_DONTCARE,
                                 L"Segoe UI");
  HFONT body_font = CreateFontW(16,
                                0,
                                0,
                                0,
                                FW_NORMAL,
                                FALSE,
                                FALSE,
                                FALSE,
                                DEFAULT_CHARSET,
                                OUT_DEFAULT_PRECIS,
                                CLIP_DEFAULT_PRECIS,
                                CLEARTYPE_QUALITY,
                                DEFAULT_PITCH | FF_DONTCARE,
                                L"Segoe UI");

  HFONT old_font = static_cast<HFONT>(SelectObject(dc, title_font));
  RECT title_rect = client_rect;
  title_rect.left += 24;
  title_rect.top += 24;
  DrawTextW(dc,
            state != NULL ? state->status_line.c_str() : L"pdfview",
            -1,
            &title_rect,
            DT_LEFT | DT_TOP | DT_SINGLELINE);

  SelectObject(dc, body_font);
  RECT body_rect = client_rect;
  body_rect.left += 24;
  body_rect.top += 72;
  body_rect.right -= 24;
  DrawTextW(dc,
            state != NULL ? state->detail_line.c_str() : L"",
            -1,
            &body_rect,
            DT_LEFT | DT_TOP | DT_WORDBREAK);

  DrawPageBitmap(dc, state);

  SelectObject(dc, old_font);
  DeleteObject(body_font);
  DeleteObject(title_font);

  EndPaint(window, &paint);
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM w_param, LPARAM l_param) {
  if (message == WM_NCCREATE) {
    const CREATESTRUCTW* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
    SetWindowLongPtrW(window,
                      GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return TRUE;
  }

  AppState* state =
      reinterpret_cast<AppState*>(GetWindowLongPtrW(window, GWLP_USERDATA));

  switch (message) {
    case WM_COMMAND: {
      switch (LOWORD(w_param)) {
        case kCommandOpen:
          ShowOpenDialogAndLoad(window, state);
          return 0;
        case kCommandExit:
          DestroyWindow(window);
          return 0;
        default:
          break;
      }
      break;
    }
    case WM_SIZE:
      RenderFirstPageToClient(window, state);
      InvalidateRect(window, NULL, TRUE);
      return 0;
    case WM_PAINT:
      PaintWindow(window, state);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
    default:
      return DefWindowProcW(window, message, w_param, l_param);
  }
}

bool LoadInitialDocument(const std::vector<std::wstring>& args, AppState* state) {
  if (state == NULL || args.size() < 2) {
    return false;
  }

  return OpenDocumentPath(NULL, args[1], state);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
  AppState state;
  ResetToEmptyState(&state);

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::vector<std::wstring> args;
  if (argv != NULL) {
    for (int index = 0; index < argc; ++index) {
      args.push_back(argv[index]);
    }
    LocalFree(argv);
  }
  LoadInitialDocument(args, &state);

  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClassName;
  window_class.hCursor = LoadCursorW(NULL, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.style = CS_HREDRAW | CS_VREDRAW;

  if (RegisterClassExW(&window_class) == 0) {
    return 1;
  }

  HWND window = CreateWindowExW(0,
                                kWindowClassName,
                                BuildWindowTitle(&state).c_str(),
                                WS_OVERLAPPEDWINDOW,
                                CW_USEDEFAULT,
                                CW_USEDEFAULT,
                                1080,
                                800,
                                NULL,
                                NULL,
                                instance,
                                &state);
  if (window == NULL) {
    return 1;
  }

  SetMenu(window, BuildMainMenu());
  RenderFirstPageToClient(window, &state);
  SetWindowTextW(window, BuildWindowTitle(&state).c_str());

  ShowWindow(window, show_command == 0 ? SW_SHOWDEFAULT : show_command);
  UpdateWindow(window);

  MSG message{};
  while (GetMessageW(&message, NULL, 0, 0) > 0) {
    if (message.message == WM_KEYDOWN && (GetKeyState(VK_CONTROL) & 0x8000) && message.wParam == 'O') {
      ShowOpenDialogAndLoad(window, &state);
      continue;
    }
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  return static_cast<int>(message.wParam);
}

#endif

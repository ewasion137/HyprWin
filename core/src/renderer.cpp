#include "../include/renderer.hpp"

// Zero-initialize all COM pointers to prevent invalid Release() calls
Renderer::Renderer() : factory(nullptr), target(nullptr), brush(nullptr), writeFactory(nullptr) {}

Renderer::~Renderer() {
  if (brush)
    brush->Release();
  if (target)
    target->Release();
  if (factory)
    factory->Release();
  if (writeFactory)
    writeFactory->Release(); // Safely release DirectWrite resource on exit
}

bool Renderer::init(HWND hwnd) {
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &factory);
  
  // Create shared DirectWrite factory
  DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown**)&writeFactory);

  RECT rc;
  GetClientRect(hwnd, &rc);

  HRESULT hr = factory->CreateHwndRenderTarget(
      D2D1::RenderTargetProperties(
          D2D1_RENDER_TARGET_TYPE_DEFAULT,
          D2D1::PixelFormat(
              DXGI_FORMAT_B8G8R8A8_UNORM,
              D2D1_ALPHA_MODE_PREMULTIPLIED) // Crucial for transparency
          ),
      D2D1::HwndRenderTargetProperties(
          hwnd, D2D1::SizeU(rc.right - rc.left, rc.bottom - rc.top)),
      &target);
  return SUCCEEDED(hr);
}

void Renderer::begin_draw() {
  if (target)
    target->BeginDraw();
}
void Renderer::end_draw() {
  if (target)
    target->EndDraw();
}

void Renderer::draw_rect(float x, float y, float w, float h, float r, float g,
                         float b, float a, float thickness) {
  if (!target) return;
  set_brush_color(r, g, b, a);
  target->DrawRectangle(D2D1::RectF(x, y, x + w, y + h), brush, thickness);
}

void Renderer::fill_rect(float x, float y, float w, float h, float r, float g, float b, float a) {
  if (!target) return;
  set_brush_color(r, g, b, a);
  target->FillRectangle(D2D1::RectF(x, y, x + w, y + h), brush);
}

void Renderer::draw_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a, float thickness) {
    if (!target) return;
    set_brush_color(r, g, b, a);
    D2D1_ROUNDED_RECT roundedRect = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->DrawRoundedRectangle(roundedRect, brush, thickness);
}

void Renderer::fill_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a) {
    if (!target) return;
    set_brush_color(r, g, b, a);
    D2D1_ROUNDED_RECT roundedRect = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->FillRoundedRectangle(roundedRect, brush);
}

// Helper: properly decode UTF-8 string to UTF-16 wstring using WinAPI
static std::wstring utf8_to_wstring(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), nullptr, 0);
  if (len <= 0) return L"";
  std::wstring result(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &result[0], len);
  return result;
}

// Render dynamic text on the transparent overlay using DirectWrite text layout
void Renderer::draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName) {
  if (!target || !writeFactory) return;

  IDWriteTextFormat* textFormat = nullptr;
  std::wstring wfont = utf8_to_wstring(fontName);
  std::wstring wtext = utf8_to_wstring(text);

  HRESULT hr = writeFactory->CreateTextFormat(
      wfont.c_str(), NULL, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, size, L"", &textFormat);

  if (SUCCEEDED(hr)) {
    IDWriteTextLayout* textLayout = nullptr;
    hr = writeFactory->CreateTextLayout(
        wtext.c_str(), (UINT32)wtext.length(), textFormat,
        2000.0f, 500.0f, &textLayout);

    if (SUCCEEDED(hr)) {
      set_brush_color(r, g, b, a);
      target->DrawTextLayout(D2D1::Point2F(x, y), textLayout, brush);
      textLayout->Release();
    }
    textFormat->Release();
  }
}

// Returns the rendered pixel width of a string, useful for right-aligning text
float Renderer::measure_text_width(const std::string& text, float size, const std::string& fontName) {
  if (!writeFactory) return 0.0f;

  IDWriteTextFormat* fmt = nullptr;
  std::wstring wfont = utf8_to_wstring(fontName);
  std::wstring wtext = utf8_to_wstring(text);

  HRESULT hr = writeFactory->CreateTextFormat(
      wfont.c_str(), NULL, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, size, L"", &fmt);

  if (!SUCCEEDED(hr)) return 0.0f;

  IDWriteTextLayout* layout = nullptr;
  hr = writeFactory->CreateTextLayout(wtext.c_str(), (UINT32)wtext.length(), fmt, 4000.0f, 500.0f, &layout);

  float width = 0.0f;
  if (SUCCEEDED(hr)) {
    DWRITE_TEXT_METRICS metrics = {};
    if (SUCCEEDED(layout->GetMetrics(&metrics)))
      width = metrics.width;
    layout->Release();
  }

  fmt->Release();
  return width;
}

// Internal helper: reuse the single brush by changing its color instead of re-creating it
void Renderer::set_brush_color(float r, float g, float b, float a) {
  if (!brush) {
    target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
  } else {
    brush->SetColor(D2D1::ColorF(r, g, b, a));
  }
}

void Renderer::clear(float r, float g, float b, float a) {
  if (target)
    target->Clear(D2D1::ColorF(r, g, b, a));
}
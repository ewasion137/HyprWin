// --- FIXED CODE LOCATOR: scripts/core/src/renderer.cpp ---
#include "../include/renderer.hpp"

// Initialize Direct2D factory and resources
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
  if (!target)
    return;
  target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
  target->DrawRectangle(D2D1::RectF(x, y, x + w, y + h), brush, thickness);
  brush->Release();
}

void Renderer::fill_rect(float x, float y, float w, float h, float r, float g, float b, float a) {
  if (!target) return;
  target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
  target->FillRectangle(D2D1::RectF(x, y, x + w, y + h), brush);
  brush->Release();
}

void Renderer::draw_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a, float thickness) {
    if (!target) return;
    target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
    D2D1_ROUNDED_RECT roundedRect = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->DrawRoundedRectangle(roundedRect, brush, thickness);
    brush->Release();
}

void Renderer::fill_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a) {
    if (!target) return;
    target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
    D2D1_ROUNDED_RECT roundedRect = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->FillRoundedRectangle(roundedRect, brush);
    brush->Release();
}

// Render dynamic text on the transparent overlay using DirectWrite text layout
void Renderer::draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName) {
  if (!target || !writeFactory) return;

  IDWriteTextFormat* textFormat = nullptr;
  std::wstring wfont(fontName.begin(), fontName.end());
  std::wstring wtext(text.begin(), text.end());

  // Create temporary text format dynamically for resizing on the fly
  HRESULT hr = writeFactory->CreateTextFormat(
      wfont.c_str(), NULL, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, size, L"", &textFormat);

  if (SUCCEEDED(hr)) {
    IDWriteTextLayout* textLayout = nullptr;
    
    // Create text layout to calculate formatting and size on the fly
    hr = writeFactory->CreateTextLayout(
        wtext.c_str(), (UINT32)wtext.length(), textFormat,
        2000.0f, 500.0f, &textLayout);

    if (SUCCEEDED(hr)) {
      target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
      
      D2D1_POINT_2F origin = D2D1::Point2F(x, y);
      
      // DrawTextLayout does NOT collide with any winuser.h macros
      target->DrawTextLayout(origin, textLayout, brush);

      brush->Release();
      textLayout->Release();
    }
    textFormat->Release();
  }
}

void Renderer::clear(float r, float g, float b, float a) {
  if (target)
    target->Clear(D2D1::ColorF(r, g, b, a));
}
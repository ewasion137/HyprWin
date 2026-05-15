#include "../include/renderer.hpp"

// Initialize Direct2D factory and resources
Renderer::Renderer() : factory(nullptr), target(nullptr), brush(nullptr) {}

Renderer::~Renderer() {
  if (brush)
    brush->Release();
  if (target)
    target->Release();
  if (factory)
    factory->Release();
}

bool Renderer::init(HWND hwnd) {
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &factory);
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

void Renderer::fill_rect(float x, float y, float w, float h, float r, float g,
                         float b, float a) {
  if (!target)
    return;
  target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
  target->FillRectangle(D2D1::RectF(x, y, x + w, y + h), brush);
  brush->Release();
}

void Renderer::clear(float r, float g, float b, float a) {
  if (target)
    target->Clear(D2D1::ColorF(r, g, b, a));
}
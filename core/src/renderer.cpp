#include "../include/renderer.hpp"
#include <unordered_map>

// Cache for IDWriteTextFormat to prevent resource exhaustion crashes
static std::unordered_map<std::wstring, IDWriteTextFormat*> g_font_cache;

Renderer::Renderer() : factory(nullptr), target(nullptr), brush(nullptr), writeFactory(nullptr) {}

Renderer::~Renderer() {
  for (auto& pair : g_font_cache) {
    if (pair.second) {
      pair.second->Release();
    }
  }
  g_font_cache.clear();

  if (brush) {
    brush->Release();
    brush = nullptr;
  }
  if (target) {
    target->Release();
    target = nullptr;
  }
  if (writeFactory) {
    writeFactory->Release();
    writeFactory = nullptr;
  }
  if (factory) {
    factory->Release();
    factory = nullptr;
  }
}

bool Renderer::init(HWND hwnd) {
  if (!IsWindow(hwnd)) {
    return false;
  }

  if (!factory) {
    HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &factory);
    if (FAILED(hr)) return false;
  }

  if (!writeFactory) {
    HRESULT hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED, 
        __uuidof(IDWriteFactory), 
        reinterpret_cast<IUnknown**>(&writeFactory)
    );
    if (FAILED(hr)) return false;
  }

  RECT rc;
  GetClientRect(hwnd, &rc);

  D2D1_SIZE_U size = D2D1::SizeU(
      rc.right - rc.left > 0 ? rc.right - rc.left : 1,
      rc.bottom - rc.top > 0 ? rc.bottom - rc.top : 1
  );

  if (target) {
    target->Release();
    target = nullptr;
  }

  HRESULT hr = factory->CreateHwndRenderTarget(
      D2D1::RenderTargetProperties(
          D2D1_RENDER_TARGET_TYPE_DEFAULT,
          D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED)
      ),
      D2D1::HwndRenderTargetProperties(hwnd, size, D2D1_PRESENT_OPTIONS_IMMEDIATELY),
      &target
  );

  return SUCCEEDED(hr);
}

void Renderer::begin_draw() {
  if (target) {
    target->BeginDraw();
  }
}

void Renderer::end_draw() {
  if (!target) return;
  HRESULT hr = target->EndDraw();
  if (hr == D2DERR_RECREATE_TARGET) {
    if (brush) {
      brush->Release();
      brush = nullptr;
    }
    target->Release();
    target = nullptr;
  }
}

void Renderer::draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float thickness) {
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

static std::wstring utf8_to_wstring(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return L"";
  std::wstring result(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), &result[0], len);
  return result;
}

static IDWriteTextFormat* get_cached_text_format(IDWriteFactory* writeFactory, const std::wstring& fontName, float size) {
  if (!writeFactory) return nullptr;
  std::wstring key = fontName + L"_" + std::to_wstring(size);
  auto it = g_font_cache.find(key);
  if (it != g_font_cache.end()) {
    return it->second;
  }

  IDWriteTextFormat* format = nullptr;
  HRESULT hr = writeFactory->CreateTextFormat(
      fontName.c_str(),
      nullptr,
      DWRITE_FONT_WEIGHT_NORMAL,
      DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL,
      size,
      L"",
      &format
  );

  if (SUCCEEDED(hr) && format) {
    g_font_cache[key] = format;
    return format;
  }
  return nullptr;
}

void Renderer::draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName) {
  if (!target || !writeFactory || text.empty()) return;

  std::wstring wfont = utf8_to_wstring(fontName);
  std::wstring wtext = utf8_to_wstring(text);

  IDWriteTextFormat* textFormat = get_cached_text_format(writeFactory, wfont, size);
  if (!textFormat) return;

  IDWriteTextLayout* textLayout = nullptr;
  HRESULT hr = writeFactory->CreateTextLayout(
      wtext.c_str(),
      static_cast<UINT32>(wtext.length()),
      textFormat,
      4000.0f,
      1000.0f,
      &textLayout
  );

  if (SUCCEEDED(hr) && textLayout) {
    set_brush_color(r, g, b, a);
    target->DrawTextLayout(D2D1::Point2F(x, y), textLayout, brush);
    textLayout->Release();
  }
}

float Renderer::measure_text_width(const std::string& text, float size, const std::string& fontName) {
  if (!writeFactory || text.empty()) return 0.0f;

  std::wstring wfont = utf8_to_wstring(fontName);
  std::wstring wtext = utf8_to_wstring(text);

  IDWriteTextFormat* textFormat = get_cached_text_format(writeFactory, wfont, size);
  if (!textFormat) return 0.0f;

  IDWriteTextLayout* layout = nullptr;
  HRESULT hr = writeFactory->CreateTextLayout(
      wtext.c_str(),
      static_cast<UINT32>(wtext.length()),
      textFormat,
      4000.0f,
      1000.0f,
      &layout
  );

  float width = 0.0f;
  if (SUCCEEDED(hr) && layout) {
    DWRITE_TEXT_METRICS metrics = {};
    if (SUCCEEDED(layout->GetMetrics(&metrics))) {
      width = metrics.width;
    }
    layout->Release();
  }
  return width;
}

void Renderer::set_brush_color(float r, float g, float b, float a) {
  if (!target) return;
  if (!brush) {
    target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
  } else {
    brush->SetColor(D2D1::ColorF(r, g, b, a));
  }
}

void Renderer::clear(float r, float g, float b, float a) {
  if (target) {
    target->Clear(D2D1::ColorF(r, g, b, a));
  }
}
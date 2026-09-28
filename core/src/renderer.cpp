#include "../include/renderer.hpp"
#include <unordered_map>

static std::unordered_map<std::wstring, IDWriteTextFormat*> g_font_cache;

static std::wstring utf8_to_wstring(const std::string& str) {
    if (str.empty()) return L"";
    int len = MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), nullptr, 0);
    if (len <= 0) return L"";
    std::wstring out(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.data(), static_cast<int>(str.size()), out.data(), len);
    return out;
}

static IDWriteTextFormat* get_cached_text_format(IDWriteFactory* factory, const std::wstring& font, float size) {
    if (!factory) return nullptr;
    std::wstring key = font + L"_" + std::to_wstring(size);
    auto it = g_font_cache.find(key);
    if (it != g_font_cache.end()) return it->second;

    IDWriteTextFormat* format = nullptr;
    HRESULT hr = factory->CreateTextFormat(
        font.c_str(),
        nullptr,
        DWRITE_FONT_WEIGHT_NORMAL,
        DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL,
        size,
        L"",
        &format
    );

    if (SUCCEEDED(hr) && format) {
        g_font_cache.emplace(std::move(key), format);
        return format;
    }
    return nullptr;
}

Renderer::Renderer() : factory(nullptr), target(nullptr), brush(nullptr), writeFactory(nullptr) {}

Renderer::~Renderer() {
    for (auto& [_, fmt] : g_font_cache) {
        if (fmt) fmt->Release();
    }
    g_font_cache.clear();

    if (brush) brush->Release();
    if (target) target->Release();
    if (writeFactory) writeFactory->Release();
    if (factory) factory->Release();
}

bool Renderer::init(HWND hwnd) {
    if (!IsWindow(hwnd)) return false;

    if (!factory && FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &factory))) {
        return false;
    }

    if (!writeFactory && FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown**>(&writeFactory)))) {
        return false;
    }

    RECT rc;
    GetClientRect(hwnd, &rc);
    D2D1_SIZE_U size = D2D1::SizeU(
        (rc.right - rc.left > 0) ? (rc.right - rc.left) : 1,
        (rc.bottom - rc.top > 0) ? (rc.bottom - rc.top) : 1
    );

    if (target) {
        target->Release();
        target = nullptr;
    }

    return SUCCEEDED(factory->CreateHwndRenderTarget(
        D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED)
        ),
        D2D1::HwndRenderTargetProperties(hwnd, size, D2D1_PRESENT_OPTIONS_IMMEDIATELY),
        &target
    ));
}

void Renderer::begin_draw() {
    if (target) target->BeginDraw();
}

void Renderer::end_draw() {
    if (!target) return;
    if (target->EndDraw() == D2DERR_RECREATE_TARGET) {
        if (brush) { brush->Release(); brush = nullptr; }
        target->Release();
        target = nullptr;
    }
}

void Renderer::clear(float r, float g, float b, float a) {
    if (target) target->Clear(D2D1::ColorF(r, g, b, a));
}

void Renderer::set_brush_color(float r, float g, float b, float a) {
    if (!target) return;
    if (!brush) {
        target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &brush);
    } else {
        brush->SetColor(D2D1::ColorF(r, g, b, a));
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
    D2D1_ROUNDED_RECT rr = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->DrawRoundedRectangle(rr, brush, thickness);
}

void Renderer::fill_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a) {
    if (!target) return;
    set_brush_color(r, g, b, a);
    D2D1_ROUNDED_RECT rr = D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), radius, radius);
    target->FillRoundedRectangle(rr, brush);
}

void Renderer::draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName) {
    if (!target || !writeFactory || text.empty()) return;

    std::wstring wfont = utf8_to_wstring(fontName);
    std::wstring wtext = utf8_to_wstring(text);

    IDWriteTextFormat* format = get_cached_text_format(writeFactory, wfont, size);
    if (!format) return;

    IDWriteTextLayout* layout = nullptr;
    HRESULT hr = writeFactory->CreateTextLayout(wtext.c_str(), static_cast<UINT32>(wtext.length()), format, 4000.0f, 1000.0f, &layout);
    if (SUCCEEDED(hr) && layout) {
        set_brush_color(r, g, b, a);
        target->DrawTextLayout(D2D1::Point2F(x, y), layout, brush);
        layout->Release();
    }
}

float Renderer::measure_text_width(const std::string& text, float size, const std::string& fontName) {
    if (!writeFactory || text.empty()) return 0.0f;

    std::wstring wfont = utf8_to_wstring(fontName);
    std::wstring wtext = utf8_to_wstring(text);

    IDWriteTextFormat* format = get_cached_text_format(writeFactory, wfont, size);
    if (!format) return 0.0f;

    IDWriteTextLayout* layout = nullptr;
    float width = 0.0f;
    HRESULT hr = writeFactory->CreateTextLayout(wtext.c_str(), static_cast<UINT32>(wtext.length()), format, 4000.0f, 1000.0f, &layout);
    if (SUCCEEDED(hr) && layout) {
        DWRITE_TEXT_METRICS metrics = {};
        if (SUCCEEDED(layout->GetMetrics(&metrics))) {
            width = metrics.width;
        }
        layout->Release();
    }
    return width;
}
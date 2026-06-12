// --- FIXED CODE LOCATOR: scripts/core/include/renderer.hpp ---
#pragma once

#include <d2d1.h>
#include <dwrite.h> // Include DirectWrite library for hardware-accelerated text rendering
#include <windows.h>
#include <string>

class Renderer {
public:
    Renderer();
    ~Renderer();
    bool init(HWND hwnd);
    void begin_draw();
    void end_draw();
    void draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float thickness);
    void fill_rect(float x, float y, float w, float h, float r, float g, float b, float a);
    void draw_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a, float thickness);
    void fill_rounded_rect(float x, float y, float w, float h, float radius, float r, float g, float b, float a);
    void clear(float r, float g, float b, float a);
    
    // Hardware-accelerated text rendering using DirectWrite text layout
    void draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName);

private:
    ID2D1Factory* factory;
    ID2D1HwndRenderTarget* target;
    ID2D1SolidColorBrush* brush;
    IDWriteFactory* writeFactory; // DirectWrite factory pointer
};
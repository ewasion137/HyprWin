#pragma once
#include <d2d1.h>
#include <string>
#include <windows.h>


// High-performance Direct2D renderer for UI and borders
class Renderer {
public:
  Renderer();
  ~Renderer();

  bool init(HWND hwnd);
  void begin_draw();
  void end_draw();

  // Basic primitives for Lua UI
  void draw_rect(float x, float y, float w, float h, float r, float g, float b,
                 float a, float thickness);
  void fill_rect(float x, float y, float w, float h, float r, float g, float b,
                 float a); // Add this
  void clear(float r, float g, float b, float a);
private:
  ID2D1Factory *factory;
  ID2D1HwndRenderTarget *target;
  ID2D1SolidColorBrush *brush;
};
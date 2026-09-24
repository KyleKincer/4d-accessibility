#pragma once
#include <cstddef>

// Bounds apply to a complete window, including repeated forms and grid pages.
// Logical grid rows live outside the ordinary node array.
namespace AXBLimits {
constexpr std::size_t nodes = 4096;
constexpr std::size_t text = 1024 * 1024;
constexpr std::size_t payload = 16 * 1024 * 1024;
}

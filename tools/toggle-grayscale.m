// Toggle macOS display grayscale (Color Filters) instantly.
//
// Uses the private UniversalAccess framework — the only way to flip grayscale
// live; `defaults write com.apple.universalaccess grayscale` does not apply
// until the accessibility daemon restarts.
//
// Build:
//   clang -framework UniversalAccess -F/System/Library/PrivateFrameworks \
//         toggle-grayscale.m -o toggle-grayscale
//
// Prints the resulting state ("on" / "off") to stdout.
#include <stdio.h>

extern void UAGrayscaleSetEnabled(int enabled);
extern int  UAGrayscaleIsEnabled(void);

int main(void) {
  int next = !UAGrayscaleIsEnabled();
  UAGrayscaleSetEnabled(next);
  printf("%s\n", next ? "on" : "off");
  return 0;
}

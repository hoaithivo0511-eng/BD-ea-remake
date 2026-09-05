#include <cmath>
#include <cstdio>
#include <string>

enum Mode { LEGACY_COMPAT = 0, PIP_UNIFIED = 1 };
static int passed = 0, failed = 0;
static void check(const char *name, bool ok) {
  if (ok) { ++passed; return; }
  ++failed; std::printf("FAIL: %s\n", name);
}
static void eq(const char *name, double got, double want, double eps=1e-12) {
  check(name, std::fabs(got-want) <= eps);
}
// Model implementation is intentionally independent from MQL source. The
// expected values below are also stated directly from broker unit definitions.
static double pip_size(bool gold, double point, int digits) {
  if (point <= 0) return 0;
  if (gold) return 0.10;
  return (digits == 3 || digits == 5) ? point * 10 : point;
}
static int legacy_scale(bool gold, double point, bool autoGold) {
  if (!autoGold || !gold || point <= 0) return 1;
  int value = (int)std::llround(0.01 / point);
  return value < 1 ? 1 : value;
}
static double legacy_point(bool gold, double point, bool autoGold) {
  return point > 0 ? point * legacy_scale(gold, point, autoGold) : 0;
}
static double config_price(double value, Mode mode, double legacyPoint, double pip) {
  return value * (mode == PIP_UNIFIED ? pip : legacyPoint);
}
static double dca_price(double value, Mode mode, double legacyPoint, double pip) {
  return value * (mode == PIP_UNIFIED ? pip : legacyPoint * 10.0);
}
static unsigned long broker_points_ceil(double price, double point) {
  if (price <= 0 || point <= 0) return 0;
  return (unsigned long)std::ceil(price / point - 1e-9);
}
static double cost_shift(double money, double lots, double tickValue, double tickSize) {
  if (lots <= 0 || tickValue <= 0 || tickSize <= 0) return 0;
  return money / (tickValue * lots) * tickSize;
}

int main() {
  eq("XAU 3d pip", pip_size(true, .001, 3), .10);
  eq("XAU 2d pip", pip_size(true, .01, 2), .10);
  eq("FX 5d pip", pip_size(false, .00001, 5), .00010);
  eq("FX 4d pip", pip_size(false, .00010, 4), .00010);
  eq("JPY 3d pip", pip_size(false, .001, 3), .010);
  eq("JPY 2d pip", pip_size(false, .01, 2), .010);

  check("XAU 3d legacy scale", legacy_scale(true, .001, true) == 10);
  check("XAU 2d legacy scale", legacy_scale(true, .01, true) == 1);
  check("AutoGold off", legacy_scale(true, .001, false) == 1);
  check("FX never gold-scaled", legacy_scale(false, .00001, true) == 1);

  double xau3Legacy = legacy_point(true, .001, true);
  double xau2Legacy = legacy_point(true, .01, true);
  double fx5Legacy = legacy_point(false, .00001, true);
  double fx4Legacy = legacy_point(false, .0001, true);
  eq("XAU legacy reference equal", xau3Legacy, xau2Legacy);
  eq("XAU legacy TP300 3d", config_price(300, LEGACY_COMPAT, xau3Legacy, .1), 3.0);
  eq("XAU legacy TP300 2d", config_price(300, LEGACY_COMPAT, xau2Legacy, .1), 3.0);
  eq("XAU unified TP300", config_price(300, PIP_UNIFIED, xau3Legacy, .1), 30.0);
  eq("FX5 legacy TP300", config_price(300, LEGACY_COMPAT, fx5Legacy, .0001), .003);
  eq("FX5 unified TP300", config_price(300, PIP_UNIFIED, fx5Legacy, .0001), .03);
  eq("FX4 legacy/unified TP300", config_price(300, LEGACY_COMPAT, fx4Legacy, .0001), .03);

  eq("XAU3 legacy DCA20", dca_price(20, LEGACY_COMPAT, xau3Legacy, .1), 2.0);
  eq("XAU2 legacy DCA20", dca_price(20, LEGACY_COMPAT, xau2Legacy, .1), 2.0);
  eq("XAU unified DCA20", dca_price(20, PIP_UNIFIED, xau3Legacy, .1), 2.0);
  eq("FX5 legacy DCA20", dca_price(20, LEGACY_COMPAT, fx5Legacy, .0001), .002);
  eq("FX5 unified DCA20", dca_price(20, PIP_UNIFIED, fx5Legacy, .0001), .002);
  eq("FX4 historical bridge", dca_price(20, LEGACY_COMPAT, fx4Legacy, .0001), .02);
  eq("FX4 unified correction", dca_price(20, PIP_UNIFIED, fx4Legacy, .0001), .002);

  check("exact broker points", broker_points_ceil(.03, .001) == 30);
  check("outward broker rounding", broker_points_ceil(.0301, .001) == 31);
  check("zero deviation", broker_points_ceil(0, .001) == 0);
  check("bad point guarded", broker_points_ceil(.1, 0) == 0);

  eq("tick cash shift", cost_shift(-10, 1, 10, .25), -.25);
  eq("tick not point regression", 1.0 - cost_shift(-10, 1, 10, .25), 1.25);
  eq("positive cost buy shift", 1.0 - cost_shift(10, 1, 10, .25), .75);
  eq("tick value guard", cost_shift(-10, 1, 0, .25), 0);
  eq("tick size guard", cost_shift(-10, 1, 10, 0), 0);

  check("invalid point profile", pip_size(false, 0, 5) == 0);
  check("legacy mode distinct on FX4 DCA", dca_price(20, LEGACY_COMPAT, fx4Legacy, .0001) != dca_price(20, PIP_UNIFIED, fx4Legacy, .0001));
  check("pips remain stable across modes", 50 * pip_size(true, .001, 3) == 5.0);

  std::printf("T17.10 unit model: %d passed, %d failed\n", passed, failed);
  if (!failed) std::puts("ALL GREEN");
  return failed ? 1 : 0;
}

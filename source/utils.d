module utils;
import std.traits;

auto clamp(T)(T val, T low, T high) if (isOrderingComparable!T) {
    if (val < low) {
        return low;
    }

    if (val > high) {
        return high;
    }

    return val;
}

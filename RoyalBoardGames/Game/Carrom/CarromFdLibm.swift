import Foundation
import GameKit

/// fdlibm 5.3 as shipped in Java's `java.lang.FdLibm` (StrictMath), ported 1:1 for the functions the Carrom engine
/// needs. Platform libms disagree in the last bit for some inputs, and one ulp in a shot angle changes a break, so
/// the engine routes every transcendental call through these: iOS reproduces the Kotlin engine bit for bit.
enum CarromFdLibm {
    // MARK: Bit access (fdlibm's __HI / __LO), as sign-extended 32-bit words

    @inline(__always) private static func HI(_ x: Double) -> Int { Int(Int32(truncatingIfNeeded: Int64(bitPattern: x.bitPattern) >> 32)) }
    @inline(__always) private static func LO(_ x: Double) -> Int { Int(Int32(truncatingIfNeeded: x.bitPattern)) }

    @inline(__always) private static func withLO(_ x: Double, _ low: Int) -> Double {
        Double(bitPattern: (x.bitPattern & 0xFFFF_FFFF_0000_0000) | UInt64(UInt32(truncatingIfNeeded: low)))
    }

    @inline(__always) private static func withHI(_ x: Double, _ high: Int) -> Double {
        Double(bitPattern: (x.bitPattern & 0x0000_0000_FFFF_FFFF) | (UInt64(UInt32(truncatingIfNeeded: high)) << 32))
    }

    @inline(__always) private static func HILO(_ high: Int, _ low: Int) -> Double {
        Double(bitPattern: (UInt64(UInt32(truncatingIfNeeded: high)) << 32) | UInt64(UInt32(truncatingIfNeeded: low)))
    }

    private static let EXP_BITS = 0x7ff0_0000
    private static let EXP_SIGNIF_BITS = 0x7fff_ffff
    private static let HUGE = 1.0e+300
    private static let TWO54 = 0x1.0p54

    // MARK: sin / cos

    static func sin(_ x: Double) -> Double {
        let ix = HI(x) & EXP_SIGNIF_BITS
        if ix <= 0x3fe9_21fb { return kernelSin(x, 0.0, 0) }
        if ix >= EXP_BITS { return x - x }
        var y0 = 0.0, y1 = 0.0
        let n = remPio2(x, &y0, &y1)
        switch n & 3 {
        case 0: return kernelSin(y0, y1, 1)
        case 1: return kernelCos(y0, y1)
        case 2: return -kernelSin(y0, y1, 1)
        default: return -kernelCos(y0, y1)
        }
    }

    static func cos(_ x: Double) -> Double {
        let ix = HI(x) & EXP_SIGNIF_BITS
        if ix <= 0x3fe9_21fb { return kernelCos(x, 0.0) }
        if ix >= EXP_BITS { return x - x }
        var y0 = 0.0, y1 = 0.0
        let n = remPio2(x, &y0, &y1)
        switch n & 3 {
        case 0: return kernelCos(y0, y1)
        case 1: return -kernelSin(y0, y1, 1)
        case 2: return -kernelCos(y0, y1)
        default: return kernelSin(y0, y1, 1)
        }
    }

    private static let S1 = -0x1.5555555555549p-3
    private static let S2 = 0x1.111111110f8a6p-7
    private static let S3 = -0x1.a01a019c161d5p-13
    private static let S4 = 0x1.71de357b1fe7dp-19
    private static let S5 = -0x1.ae5e68a2b9cebp-26
    private static let S6 = 0x1.5d93a5acfd57cp-33

    private static func kernelSin(_ x: Double, _ y: Double, _ iy: Int) -> Double {
        let ix = HI(x) & EXP_SIGNIF_BITS
        if ix < 0x3e40_0000 {
            if Kt.toInt(x) == 0 { return x }
        }
        let z = x * x
        let v = z * x
        let r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
        if iy == 0 {
            return x + v * (S1 + z * r)
        } else {
            return x - ((z * (0.5 * y - v * r) - y) - v * S1)
        }
    }

    private static let C1 = 0x1.555555555554cp-5
    private static let C2 = -0x1.6c16c16c15177p-10
    private static let C3 = 0x1.a01a019cb159p-16
    private static let C4 = -0x1.27e4f809c52adp-22
    private static let C5 = 0x1.1ee9ebdb4b1c4p-29
    private static let C6 = -0x1.8fae9be8838d4p-37

    private static func kernelCos(_ x: Double, _ y: Double) -> Double {
        let ix = HI(x) & EXP_SIGNIF_BITS
        if ix < 0x3e40_0000 {
            if Kt.toInt(x) == 0 { return 1.0 }
        }
        let z = x * x
        let r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
        if ix < 0x3FD3_3333 {
            return 1.0 - (0.5 * z - (z * r - x * y))
        } else {
            let qx: Double = ix > 0x3fe9_0000 ? 0.28125 : HILO(ix - 0x0020_0000, 0)
            let hz = 0.5 * z - qx
            let a = 1.0 - qx
            return a - (hz - (z * r - x * y))
        }
    }

    private static let npio2_hw: [Int] = [
        0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
        0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C,
        0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
        0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
        0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
        0x404858EB, 0x404921FB,
    ]

    private static let invpio2 = 0x1.45f306dc9c883p-1
    private static let pio2_1 = 0x1.921fb544p0
    private static let pio2_1t = 0x1.0b4611a626331p-34
    private static let pio2_2 = 0x1.0b4611a6p-34
    private static let pio2_2t = 0x1.3198a2e037073p-69
    private static let pio2_3 = 0x1.3198a2ep-69
    private static let pio2_3t = 0x1.b839a252049c1p-104

    /// __ieee754_rem_pio2 for |x| up to 2^19·π/2 (Carrom angles stay within a few radians).
    private static func remPio2(_ x: Double, _ y0: inout Double, _ y1: inout Double) -> Int {
        let hx = HI(x)
        let ix = hx & EXP_SIGNIF_BITS
        if ix <= 0x3fe9_21fb {
            y0 = x
            y1 = 0
            return 0
        }
        if ix < 0x4002_d97c {
            if hx > 0 {
                var z = x - pio2_1
                if ix != 0x3ff9_21fb {
                    y0 = z - pio2_1t
                    y1 = (z - y0) - pio2_1t
                } else {
                    z -= pio2_2
                    y0 = z - pio2_2t
                    y1 = (z - y0) - pio2_2t
                }
                return 1
            } else {
                var z = x + pio2_1
                if ix != 0x3ff9_21fb {
                    y0 = z + pio2_1t
                    y1 = (z - y0) + pio2_1t
                } else {
                    z += pio2_2
                    y0 = z + pio2_2t
                    y1 = (z - y0) + pio2_2t
                }
                return -1
            }
        }
        if ix <= 0x4139_21fb {
            var t = Swift.abs(x)
            let n = Kt.toInt(t * invpio2 + 0.5)
            let fn = Double(n)
            var r = t - fn * pio2_1
            var w = fn * pio2_1t
            if n < 32 && ix != npio2_hw[n - 1] {
                y0 = r - w
            } else {
                let j = ix >> 20
                y0 = r - w
                var i = j - ((HI(y0) >> 20) & 0x7ff)
                if i > 16 {
                    t = r
                    w = fn * pio2_2
                    r = t - w
                    w = fn * pio2_2t - ((t - r) - w)
                    y0 = r - w
                    i = j - ((HI(y0) >> 20) & 0x7ff)
                    if i > 49 {
                        t = r
                        w = fn * pio2_3
                        r = t - w
                        w = fn * pio2_3t - ((t - r) - w)
                        y0 = r - w
                    }
                }
            }
            y1 = (r - y0) - w
            if hx < 0 {
                y0 = -y0
                y1 = -y1
                return -n
            }
            return n
        }
        if ix >= EXP_BITS {
            y0 = x - x
            y1 = y0
            return 0
        }
        // Huge arguments never occur in the engine; reduce with the platform for completeness.
        let n = Kt.toInt((x * invpio2).rounded(.toNearestOrEven))
        let r = x - Double(n) * (Double.pi / 2)
        y0 = r
        y1 = 0
        return n
    }

    // MARK: atan / atan2

    private static let atanhi: [Double] = [0x1.dac670561bb4fp-2, 0x1.921fb54442d18p-1, 0x1.f730bd281f69bp-1, 0x1.921fb54442d18p0]
    private static let atanlo: [Double] = [0x1.a2b7f222f65e2p-56, 0x1.1a62633145c07p-55, 0x1.007887af0cbbdp-56, 0x1.1a62633145c07p-54]
    private static let aT: [Double] = [
        0x1.555555555550dp-2, -0x1.999999998ebc4p-3, 0x1.24924920083ffp-3, -0x1.c71c6fe231671p-4,
        0x1.745cdc54c206ep-4, -0x1.3b0f2af749a6dp-4, 0x1.10d66a0d03d51p-4, -0x1.dde2d52defd9ap-5,
        0x1.97b4b24760debp-5, -0x1.2b4442c6a6c2fp-5, 0x1.0ad3ae322da11p-6,
    ]

    static func atan(_ xIn: Double) -> Double {
        var x = xIn
        let hx = HI(x)
        let ix = hx & EXP_SIGNIF_BITS
        var id: Int
        if ix >= 0x4410_0000 {
            if ix > EXP_BITS || (ix == EXP_BITS && LO(x) != 0) { return x + x }
            return hx > 0 ? atanhi[3] + atanlo[3] : -atanhi[3] - atanlo[3]
        }
        if ix < 0x3fdc_0000 {
            if ix < 0x3e20_0000 {
                if HUGE + x > 1.0 { return x }
            }
            id = -1
        } else {
            x = Swift.abs(x)
            if ix < 0x3ff3_0000 {
                if ix < 0x3fe6_0000 {
                    id = 0
                    x = (2.0 * x - 1.0) / (2.0 + x)
                } else {
                    id = 1
                    x = (x - 1.0) / (x + 1.0)
                }
            } else {
                if ix < 0x4003_8000 {
                    id = 2
                    x = (x - 1.5) / (1.0 + 1.5 * x)
                } else {
                    id = 3
                    x = -1.0 / x
                }
            }
        }
        var z = x * x
        let w = z * z
        let s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))))
        let s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))))
        if id < 0 {
            return x - x * (s1 + s2)
        } else {
            z = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x)
            return hx < 0 ? -z : z
        }
    }

    private static let tiny = 1.0e-300
    private static let pi_o_4 = 0x1.921fb54442d18p-1
    private static let pi_o_2 = 0x1.921fb54442d18p0
    private static let pi_lo = 0x1.1a62633145c07p-53

    static func atan2(_ y: Double, _ x: Double) -> Double {
        let hx = HI(x)
        let ix = hx & EXP_SIGNIF_BITS
        let lx = LO(x)
        let hy = HI(y)
        let iy = hy & EXP_SIGNIF_BITS
        let ly = LO(y)
        if x.isNaN || y.isNaN { return x + y }
        if ((hx - 0x3ff0_0000) | lx) == 0 { return atan(y) }
        let m = ((hy >> 31) & 1) | ((hx >> 30) & 2)
        if (iy | ly) == 0 {
            switch m {
            case 0, 1: return y
            case 2: return Double.pi + tiny
            default: return -Double.pi - tiny
            }
        }
        if (ix | lx) == 0 { return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny }
        if ix == EXP_BITS {
            if iy == EXP_BITS {
                switch m {
                case 0: return pi_o_4 + tiny
                case 1: return -pi_o_4 - tiny
                case 2: return 3.0 * pi_o_4 + tiny
                default: return -3.0 * pi_o_4 - tiny
                }
            } else {
                switch m {
                case 0: return 0.0
                case 1: return -0.0
                case 2: return Double.pi + tiny
                default: return -Double.pi - tiny
                }
            }
        }
        if iy == EXP_BITS { return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny }
        let k = (iy - ix) >> 20
        let z: Double
        if k > 60 {
            z = pi_o_2 + 0.5 * pi_lo
        } else if hx < 0 && k < -60 {
            z = 0.0
        } else {
            z = atan(Swift.abs(y / x))
        }
        switch m {
        case 0: return z
        case 1: return -z
        case 2: return Double.pi - (z - pi_lo)
        default: return (z - pi_lo) - Double.pi
        }
    }

    // MARK: log

    private static let ln2_hi = 0x1.62e42feep-1
    private static let ln2_lo = 0x1.a39ef35793c76p-33
    private static let Lg1 = 0x1.5555555555593p-1
    private static let Lg2 = 0x1.999999997fa04p-2
    private static let Lg3 = 0x1.2492494229359p-2
    private static let Lg4 = 0x1.c71c51d8e78afp-3
    private static let Lg5 = 0x1.7466496cb03dep-3
    private static let Lg6 = 0x1.39a09d078c69fp-3
    private static let Lg7 = 0x1.2f112df3e5244p-3

    static func log(_ xIn: Double) -> Double {
        var x = xIn
        var hx = HI(x)
        let lx = LO(x)
        var k = 0
        if hx < 0x0010_0000 {
            if ((hx & EXP_SIGNIF_BITS) | lx) == 0 { return -TWO54 / 0.0 }
            if hx < 0 { return (x - x) / 0.0 }
            k -= 54
            x *= TWO54
            hx = HI(x)
        }
        if hx >= EXP_BITS { return x + x }
        k += (hx >> 20) - 1023
        hx &= 0x000f_ffff
        var i = (hx + 0x9_5f64) & 0x10_0000
        x = withHI(x, hx | (i ^ 0x3ff0_0000))
        k += (i >> 20)
        let f = x - 1.0
        if (0x000f_ffff & (2 + hx)) < 3 {
            if f == 0.0 {
                if k == 0 { return 0.0 }
                let dk = Double(k)
                return dk * ln2_hi + dk * ln2_lo
            }
            let R = f * f * (0.5 - 0.33333333333333333 * f)
            if k == 0 { return f - R }
            let dk = Double(k)
            return dk * ln2_hi - ((R - dk * ln2_lo) - f)
        }
        let s = f / (2.0 + f)
        let dk = Double(k)
        let z = s * s
        i = hx - 0x6_147a
        let w = z * z
        let j = 0x6b851 - hx
        let t1 = w * (Lg2 + w * (Lg4 + w * Lg6))
        let t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)))
        i |= j
        let R = t2 + t1
        if i > 0 {
            let hfsq = 0.5 * f * f
            if k == 0 { return f - (hfsq - s * (hfsq + R)) }
            return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f)
        } else {
            if k == 0 { return f - s * (f - R) }
            return dk * ln2_hi - ((s * (f - R) - dk * ln2_lo) - f)
        }
    }

    // MARK: pow

    static func pow(_ x: Double, _ y: Double) -> Double {
        var z: Double
        var r, s, t, u, v, w: Double
        var i, j, k, n: Int

        if y == 0.0 { return 1.0 }
        if x.isNaN || y.isNaN { return x + y }

        let y_abs = Swift.abs(y)
        var x_abs = Swift.abs(x)
        if y == 2.0 {
            return x * x
        } else if y == 0.5 {
            if x >= -Double.greatestFiniteMagnitude { return (x + 0.0).squareRoot() }
        } else if y_abs == 1.0 {
            return y == 1.0 ? x : 1.0 / x
        } else if y_abs == Double.infinity {
            if x_abs == 1.0 { return y - y }
            if x_abs > 1.0 { return y >= 0 ? y : 0.0 }
            return y < 0 ? -y : 0.0
        }

        let hx = HI(x)
        var ix = hx & EXP_SIGNIF_BITS

        var y_is_int = 0
        if hx < 0 {
            if y_abs >= 0x1.0p53 {
                y_is_int = 2
            } else if y_abs >= 1.0 {
                let y_abs_as_long = Kt.toLong(y_abs)
                if Double(y_abs_as_long) == y_abs { y_is_int = 2 - Int(y_abs_as_long & 0x1) }
            }
        }

        if x_abs == 0.0 || x_abs == Double.infinity || x_abs == 1.0 {
            z = x_abs
            if y < 0.0 { z = 1.0 / z }
            if hx < 0 {
                if ((ix - 0x3ff0_0000) | y_is_int) == 0 {
                    z = (z - z) / (z - z)
                } else if y_is_int == 1 {
                    z = -1.0 * z
                }
            }
            return z
        }

        n = (hx >> 31) + 1
        if (n | y_is_int) == 0 { return (x - x) / (x - x) }

        s = 1.0
        if (n | (y_is_int - 1)) == 0 { s = -1.0 }

        var p_h, p_l, t1, t2: Double
        if y_abs > 0x1.00000ffffffffp31 {
            let INV_LN2 = 0x1.71547652b82fep0
            let INV_LN2_H = 0x1.715476p0
            let INV_LN2_L = 0x1.4ae0bf85ddf44p-26
            if x_abs < 0x1.fffff00000000p-1 { return y < 0.0 ? s * Double.infinity : s * 0.0 }
            if x_abs > 0x1.00000ffffffffp0 { return y > 0.0 ? s * Double.infinity : s * 0.0 }
            t = x_abs - 1.0
            w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
            u = INV_LN2_H * t
            v = t * INV_LN2_L - w * INV_LN2
            t1 = u + v
            t1 = withLO(t1, 0)
            t2 = v - (t1 - u)
        } else {
            let CP = 0x1.ec709dc3a03fdp-1
            let CP_H = 0x1.ec709ep-1
            let CP_L = -0x1.e2fe0145b01f5p-28
            var z_h, z_l, ss, s2, s_h, s_l, t_h, t_l: Double
            n = 0
            if ix < 0x0010_0000 {
                x_abs *= 0x1.0p53
                n -= 53
                ix = HI(x_abs)
            }
            n += (ix >> 20) - 0x3ff
            j = ix & 0x000f_ffff
            ix = j | 0x3ff0_0000
            if j <= 0x3988E {
                k = 0
            } else if j < 0xBB67A {
                k = 1
            } else {
                k = 0
                n += 1
                ix -= 0x0010_0000
            }
            x_abs = withHI(x_abs, ix)

            let BP: [Double] = [1.0, 1.5]
            let DP_H: [Double] = [0.0, 0x1.2b8034p-1]
            let DP_L: [Double] = [0.0, 0x1.cfdeb43cfd006p-27]
            let L1 = 0x1.3333333333303p-1
            let L2 = 0x1.b6db6db6fabffp-2
            let L3 = 0x1.55555518f264dp-2
            let L4 = 0x1.17460a91d4101p-2
            let L5 = 0x1.d864a93c9db65p-3
            let L6 = 0x1.a7e284a454eefp-3
            u = x_abs - BP[k]
            v = 1.0 / (x_abs + BP[k])
            ss = u * v
            s_h = ss
            s_h = withLO(s_h, 0)
            t_h = 0.0
            t_h = withHI(t_h, ((ix >> 1) | 0x2000_0000) + 0x0008_0000 + (k << 18))
            t_l = x_abs - (t_h - BP[k])
            s_l = v * ((u - s_h * t_h) - s_h * t_l)
            s2 = ss * ss
            r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))))
            r += s_l * (s_h + ss)
            s2 = s_h * s_h
            t_h = 3.0 + s2 + r
            t_h = withLO(t_h, 0)
            t_l = r - ((t_h - 3.0) - s2)
            u = s_h * t_h
            v = s_l * t_h + t_l * ss
            p_h = u + v
            p_h = withLO(p_h, 0)
            p_l = v - (p_h - u)
            z_h = CP_H * p_h
            z_l = CP_L * p_h + p_l * CP + DP_L[k]
            t = Double(n)
            t1 = (((z_h + z_l) + DP_H[k]) + t)
            t1 = withLO(t1, 0)
            t2 = z_l - (((t1 - t) - DP_H[k]) - z_h)
        }

        var y1 = y
        y1 = withLO(y1, 0)
        p_l = (y - y1) * t1 + y * t2
        p_h = y1 * t1
        z = p_l + p_h
        j = HI(z)
        i = LO(z)
        if j >= 0x4090_0000 {
            if ((j - 0x4090_0000) | i) != 0 {
                return s * Double.infinity
            } else {
                let OVT = 8.0085662595372944372e-0017
                if p_l + OVT > z - p_h { return s * Double.infinity }
            }
        } else if (j & EXP_SIGNIF_BITS) >= 0x4090_cc00 {
            if ((j - Int(Int32(bitPattern: 0xc090_cc00))) | i) != 0 {
                return s * 0.0
            } else {
                if p_l <= z - p_h { return s * 0.0 }
            }
        }
        let P1 = 0x1.555555555553ep-3
        let P2 = -0x1.6c16c16bebd93p-9
        let P3 = 0x1.1566aaf25de2cp-14
        let P4 = -0x1.bbd41c5d26bf1p-20
        let P5 = 0x1.6376972bea4d0p-25
        let LG2 = 0x1.62e42fefa39efp-1
        let LG2_H = 0x1.62e43p-1
        let LG2_L = -0x1.05c610ca86c39p-29
        i = j & EXP_SIGNIF_BITS
        k = (i >> 20) - 0x3ff
        n = 0
        if i > 0x3fe0_0000 {
            n = j + (0x0010_0000 >> (k + 1))
            k = ((n & EXP_SIGNIF_BITS) >> 20) - 0x3ff
            t = 0.0
            t = withHI(t, n & ~(0x000f_ffff >> k))
            n = ((n & 0x000f_ffff) | 0x0010_0000) >> (20 - k)
            if j < 0 { n = -n }
            p_h -= t
        }
        t = p_l + p_h
        t = withLO(t, 0)
        u = t * LG2_H
        v = (p_l - (t - p_h)) * LG2 + t * LG2_L
        z = u + v
        w = v - (z - u)
        t = z * z
        t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
        r = (z * t1) / (t1 - 2.0) - (w + z * w)
        z = 1.0 - (r - z)
        j = HI(z)
        j += (n << 20)
        if (j >> 20) <= 0 {
            z = Foundation.scalbn(z, n)
        } else {
            var z_hi = HI(z)
            z_hi += (n << 20)
            z = withHI(z, z_hi)
        }
        return s * z
    }
}

package com.ngstudio.royalboardgames.game.carrom.strict

/**
 * Golden-dump shim: the Carrom engine's kotlin.math calls routed through StrictMath (fdlibm), so the reference
 * is platform independent. On HotSpot aarch64 Math.sin/cos are intrinsics that differ from fdlibm in ~7% of
 * inputs; Math.atan2/log/pow already equal StrictMath there (checked on 3M samples), so only sin/cos change.
 */
fun sin(x: Double): Double = StrictMath.sin(x)
fun cos(x: Double): Double = StrictMath.cos(x)
fun atan2(y: Double, x: Double): Double = StrictMath.atan2(y, x)
fun ln(x: Double): Double = StrictMath.log(x)
fun Double.pow(x: Double): Double = StrictMath.pow(this, x)

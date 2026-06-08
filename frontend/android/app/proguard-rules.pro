# ── Razorpay ─────────────────────────────────────────────────────────────────
-keep class com.razorpay.** { *; }
-keepclassmembers class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# Proguard rules for Razorpay dependencies
-keep class org.json.** { *; }
-dontwarn org.json.**

# ── Flutter / Dart VM ─────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── OkHttp / Retrofit (used internally by some plugins) ──────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ── Keep all model classes used with JSON serialization ──────────────────────
# (dart:convert works at runtime, no reflection needed — this is a safety net)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod

# ── Google Play Core (required by Flutter split-install plugin) ───────────────
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# ── AndroidX ─────────────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**

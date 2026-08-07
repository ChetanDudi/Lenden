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

# ── Firebase & Google Sign-In / Phone Auth ───────────────────────────────────
# Without these rules R8/ProGuard strips Firebase reflection-based classes and
# breaks both Google Sign-In (error 12500) and Firebase phone authentication.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes InnerClasses
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── ML Kit Text Recognition (only the Latin script is bundled; the plugin's ──
# ── code references the optional Chinese/Devanagari/Japanese/Korean ──────────
# ── recognizers even when their dependencies aren't included) ────────────────
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

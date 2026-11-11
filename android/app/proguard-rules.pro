# ProGuard / R8 Rules for Release Build (HygieneTruth)

# Flutter Engine & Deferred Components
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.**

# Google Play Core & Deferred Components (Split Install)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-keep class com.google.android.play.core.** { *; }

# Google ML Kit Text Recognition (Include and suppress optional language modules)
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**
-dontwarn com.google_mlkit_text_recognition.**
-dontwarn com.google_mlkit_commons.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }

# Stripe Android SDK Rules
-keep class com.stripe.android.** { *; }
-dontwarn com.stripe.android.**
-keep class com.stripe.android.paymentsheet.** { *; }
-keep class com.facebook.react.bridge.** { *; }

# Supabase & GoTrue / Realtime
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# Firebase Messaging & Core
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Maps & Play Services
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Speech To Text
-keep class com.csdcorp.speech_to_text.** { *; }
-dontwarn com.csdcorp.speech_to_text.**

# Desugaring & Kotlin Coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Crypto & Security
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

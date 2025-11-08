# Flutter and Dart ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Agora RTC Engine - CRITICAL for voice meetings
-keep class io.agora.**{*;}
-dontwarn io.agora.**

# Firebase
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase AI / Generative AI
-keep class com.google.ai.** { *; }
-dontwarn com.google.ai.**

# Preserve native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }

# Record package (audio recording)
-keep class com.llfbandit.record.** { *; }
-dontwarn com.llfbandit.record.**

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Image picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# QR/Barcode scanner
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# General Android components
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Gson rules (flutter_local_notifications relies on Gson TypeToken; R8 strips
# generic signatures by default, breaking loadScheduledNotifications() and
# pendingNotificationRequests() with "TypeToken must be created with a type
# argument". These rules come from the plugin's own example app.)
-keepattributes Signature

# For using GSON @Expose annotation
-keepattributes *Annotation*

# Gson specific classes
-dontwarn sun.misc.**
#-keep class com.google.gson.stream.** { *; }

# Prevent proguard from stripping interface information from TypeAdapter,
# TypeAdapterFactory, JsonSerializer, JsonDeserializer instances (so they can
# be used in @JsonAdapter)
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Retain generic signatures of TypeToken and its subclasses with R8 version
# 3.0 and higher.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# flutter_local_notifications: keep the plugin's model classes and receivers
# intact (they are serialized to/from JSON and referenced from the manifest).
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Razorpay checkout --------------------------------------------------------
# Release builds run R8 with minify + shrink enabled. The Razorpay SDK is
# driven from Dart through reflection and serializes its own models, so
# shrinking it breaks checkout in release APKs only — the exact class of bug
# that never shows up in a debug build. Keep the SDK and the WebView bridge.
-keep class com.razorpay.** { *; }
-keep interface com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keepclassmembers class * {
  @android.webkit.JavascriptInterface <methods>;
}
-keepclassmembers class * {
  public static final <fields>;
}
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# R8/ProGuard keep rules for the release build.
#
# The Flutter Gradle plugin already contributes the core engine keep rules; the
# Android manifest keeps our receivers/services/activity automatically. These
# rules cover the rest and silence harmless "missing class" notes from optional
# code paths in dependencies.

# Flutter embedding (belt-and-suspenders; the plugin keeps these too).
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# AndroidX core (NotificationCompat etc.).
-dontwarn androidx.**

# Keep annotations and Kotlin metadata used by reflection in AndroidX.
-keepattributes *Annotation*, InnerClasses, Signature, Exceptions

# Our app package — referenced from the manifest, but keep names stable.
-keep class com.smsguard.sms_bllocker.** { *; }

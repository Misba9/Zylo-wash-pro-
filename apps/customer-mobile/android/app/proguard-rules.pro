# WashPro release rules (R8)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.gson.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Razorpay Standard Checkout (required when minifyEnabled=true).
# Without these, UPI Intent / Checkout callbacks can break in release builds.
# Source: razorpay_flutter README Proguard rules
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

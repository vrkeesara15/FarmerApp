# SEC-008 release shrinking / obfuscation (R8). Flutter and the plugins ship
# their own consumer rules; these cover reflection the defaults miss.

# flutter_local_notifications stores scheduled notifications with Gson generics.
-keepattributes Signature
-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Play Integrity (SEC-024) ships consumer rules; keep the task API stable.
-keep class com.google.android.play.core.integrity.** { *; }

# Play core deferred components are not used; silence R8 about Flutter's refs.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

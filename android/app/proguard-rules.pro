# LiteRT / TFLite JNI bridge — prevent R8 from stripping the native binding classes.
-keep class com.google.ai.edge.litert.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn com.google.ai.edge.litert.**
-dontwarn org.tensorflow.lite.**

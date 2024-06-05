// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference;
import io.flutter.plugin.common.MethodChannel;

/**
 * Plugin for controlling a set of MapLibreMap views to be shown as overlays on top of the Flutter
 * view. The overlay should be hidden during transformations or while Flutter is rendering on top of
 * the map. A Texture drawn using MapLibreMap bitmap snapshots can then be shown instead of the
 * overlay.
 */
public class MapLibreMapsPlugin implements FlutterPlugin, ActivityAware {
<<<<<<<< HEAD:maplibre_gl/android/src/main/java/org/maplibre/maplibregl/MapLibreMapsPlugin.java
========

  private static final String VIEW_TYPE = "plugins.flutter.io/mapbox_gl";
>>>>>>>> 547c457 (feat!: migrate `maplibre-native` for android to version `11.0.0` (take 2) (#406)):android/src/main/java/org/maplibre/maplibregl/MapLibreMapsPlugin.java

  static FlutterAssets flutterAssets;
  private Lifecycle lifecycle;

  public MapLibreMapsPlugin() {
    // no-op
  }

  // New Plugin APIs

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    flutterAssets = binding.getFlutterAssets();

    MethodChannel methodChannel =
        new MethodChannel(binding.getBinaryMessenger(), "plugins.flutter.io/maplibre_gl");
    methodChannel.setMethodCallHandler(new GlobalMethodHandler(binding));

    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
<<<<<<<< HEAD:maplibre_gl/android/src/main/java/org/maplibre/maplibregl/MapLibreMapsPlugin.java
            "plugins.flutter.io/maplibre_gl",
========
            "plugins.flutter.io/mapbox_gl",
>>>>>>>> 547c457 (feat!: migrate `maplibre-native` for android to version `11.0.0` (take 2) (#406)):android/src/main/java/org/maplibre/maplibregl/MapLibreMapsPlugin.java
            new MapLibreMapFactory(
                binding.getBinaryMessenger(),
                new LifecycleProvider() {
                  @Nullable
                  @Override
                  public Lifecycle getLifecycle() {
                    return lifecycle;
                  }
                }));
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    // no-op
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    lifecycle = null;
  }


  interface LifecycleProvider {
    @Nullable
    Lifecycle getLifecycle();
  }

  /** Provides a static method for extracting lifecycle objects from Flutter plugin bindings. */
  public static class FlutterLifecycleAdapter {

    /**
     * Returns the lifecycle object for the activity a plugin is bound to.
     *
     * <p>Returns null if the Flutter engine version does not include the lifecycle extraction code.
     * (this probably means the Flutter engine version is too old).
     */
    @NonNull
    public static Lifecycle getActivityLifecycle(
        @NonNull ActivityPluginBinding activityPluginBinding) {
      HiddenLifecycleReference reference =
          (HiddenLifecycleReference) activityPluginBinding.getLifecycle();
      return reference.getLifecycle();
    }
  }
}

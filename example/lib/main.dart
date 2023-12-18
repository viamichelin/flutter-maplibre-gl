// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:maplibre_gl_example/vector_map.dart';

class MapsDemo extends StatefulWidget {
  const MapsDemo({super.key});

  @override
  State<MapsDemo> createState() => _MapsDemoState();
}

class _MapsDemoState extends State<MapsDemo> {
  final _mapKey = GlobalKey<VectorMapState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VectorMap(key: _mapKey),
      floatingActionButton: FloatingActionButton(
        child: const Text("Ad.Ic"),
        onPressed: () async {
          _mapKey.currentState!.drawIcon(
            VectorMapIcon(
              latLng: const LatLng(50.853905, 4.363775),
              identifier: "location_selected",
              iconPath: "assets/location_selected.png",
            ),
          );
        },
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(home: MapsDemo()));
}

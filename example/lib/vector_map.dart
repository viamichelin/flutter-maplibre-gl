import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:convert';

class VectorMapIcon {
  final LatLng latLng;
  final String identifier;
  final String iconPath;

  VectorMapIcon({
    required this.latLng,
    required this.identifier,
    required this.iconPath,
  });
}

class VectorMap extends StatefulWidget {
  final CameraPosition initialCameraPosition;

  final List<LatLng>? route;

  /// Will be called whenever the user clicks on an specify point on the map.
  /// It doesn't matter if the user long presses or just a short tap on any point.
  /// The received [LatLng] is the click point of the user.
  final void Function(LatLng latLng)? onMapClicked;

  const VectorMap({
    super.key,
    this.initialCameraPosition = const CameraPosition(
      target: LatLng(50.834060793873505, 4.340443996254663),
      zoom: 12,
    ),
    this.route,
    this.onMapClicked,
  });

  @override
  State<VectorMap> createState() => VectorMapState();
}

class VectorMapState extends State<VectorMap> {
  static const _routeDefaultPadding = 40.0;

  @visibleForTesting
  static const cameraFocusZoom = 16.5;

  /// This value is used to check if the zoom needs to be adjusted during the [CameraUpdate] or not.
  /// The current zoom +- [acceptedZoomPadding] is fine and there is no need to change anything.
  @visibleForTesting
  static const acceptedZoomPadding = 1.0;

  var _styleLoadedCompleter = Completer<void>();
  final _mapReadyCompleter = Completer<MaplibreMapController>();

  /// The key is the created identifier by the [SymbolOptions]
  /// the value is the object from the user.
  final _symbolMap = <String, VectorMapIcon>{};

  /// There is no need to create the same image multiple times, that why we cache the identifier.
  final _cachedImages = <String>[];

  Brightness? _previousBrightness;

  @override
  void initState() {
    super.initState();

    final route = widget.route;
    if (route != null) {
      drawRoute(points: route, animateCamera: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // Initialize if never set.
    _previousBrightness ??= brightness;

    // We need to change the id, otherwise the id is the same and the style is not correctly used
    const styleUrl =
        "https://api.maptiler.com/maps/3dd4d51b-ae78-4074-8b31-b47a49f1b5ce/style.json?key=kZ5xAKKbPzxo3GeJ2odT";

    if (_previousBrightness != brightness) {
      _previousBrightness = brightness;
      _scheduleGeometryRedraw();
    }

    final onMapClicked = widget.onMapClicked;

    return MaplibreMap(
      initialCameraPosition: widget.initialCameraPosition,
      // ⚠️ MapBox styles are not supported! -> https://github.com/maplibre/flutter-maplibre-gl/issues/149
      styleString: styleUrl,
      compassEnabled: false,
      // We show an custom indicator for the current location, since we want some custom handling.
      myLocationEnabled: false,
      // We disable the different perspective, since the style doesn't
      // support that feature in 3d.
      // https://www.nextpit.com/forum/561686/how-to-use-google-maps-secret-gestures
      tiltGesturesEnabled: false,
      onMapClick:
          onMapClicked == null ? null : (_, latLng) => onMapClicked(latLng),
      onMapCreated: (controller) {
        onNextFrame(() => _mapReadyCompleter.complete(controller));
      },
      onStyleLoadedCallback: () {
        // We are not using "completeOnce" here because we should never
        // run into the issue that this is already completed.
        // Every time we change the style we are creating a fresh completer
        // and we wait for the completer to finish.
        _styleLoadedCompleter.complete();

        fadeoutNotImportantAreas();

        setMapLanguage();
      },
      // Need to be true to receive the change events from the move, zoom and scale events
      // that are done with the [MaplibreMapController]
      trackCameraPosition: true,
      annotationOrder: const [
        AnnotationType.fill,
        AnnotationType.circle,
        AnnotationType.line,
        AnnotationType.symbol,
      ],
    );
  }

  @override
  void didUpdateWidget(covariant VectorMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newRoute = widget.route;

    final isMapReady =
        _mapReadyCompleter.isCompleted && _styleLoadedCompleter.isCompleted;

    // ⚠️ "late" since the operation is quite expensive and
    // we don't need to do that every time before the map is ready
    late final isSameRoute =
        const ListEquality<LatLng>().equals(oldWidget.route, newRoute);

    // Do not draw a route if the map wasn't initialized yet.
    // We already triggered a _drawRoute from initState which will
    // take care of drawing the current route.
    // Otherwise we end up with multiple calls to _drawRoute which is not necessary.
    if (isMapReady && !isSameRoute) {
      removeRoute();

      if (newRoute != null) {
        drawRoute(points: newRoute, animateCamera: true);
      }
    }
  }

  // region public

  Future<void> removeRoute() async {
    final controller = await _getController();

    if (!mounted) return;

    if (controller.lines.isNotEmpty) {
      await controller.removeLines(controller.lines);
    }
  }

  Future<void> removeCurrentUserLocation() async {
    final controller = await _getController();
    if (!mounted) return;

    for (final circle in controller.circles) {
      await controller.removeCircle(circle);
    }
  }

  Future<void> drawIcon(
    VectorMapIcon mapIcon, {
    required bool animateCamera,
  }) async {
    final controller = await _getController();
    if (!mounted) return;

    await _addImageToCacheIfNeeded(controller, mapIcon: mapIcon);

    await removeIcon(identifier: mapIcon.identifier);

    final symbol = await controller.addSymbol(
      SymbolOptions(
        geometry: mapIcon.latLng,
        iconImage: mapIcon.identifier,
      ),
    );

    _symbolMap[symbol.id] = mapIcon;

    if (animateCamera) {
      await animateCameraTo(latLng: mapIcon.latLng);
    }
  }

  Future<void> removeIcons() async {
    final controller = await _getController();

    if (!mounted) return;

    final symbols = controller.symbols;

    if (symbols.isEmpty) return;

    await controller.removeSymbols(symbols);
  }

  Future<void> removeIcon({
    required String identifier,
  }) async {
    final controller = await _getController();

    if (!mounted) return;

    final searchedSymbolId = _symbolMap.entries
        .firstWhereOrNull((entry) => entry.value.identifier == identifier)
        ?.key;

    if (searchedSymbolId == null) {
      return;
    }

    final symbol = controller.symbols
        .firstWhereOrNull((symbol) => symbol.id == searchedSymbolId);

    if (symbol == null) {
      return;
    }

    await controller.removeSymbol(symbol);
    _symbolMap.remove(symbol.id);
  }

  /// Move cameras center to the [latLng] with zoom in by [cameraFocusZoom]
  Future<void> animateCameraTo({required LatLng latLng}) async {
    final controller = await _getController();
    if (!mounted) return;

    final previousZoom = controller.cameraPosition?.zoom;

    final CameraUpdate cameraUpdate;

    if (shouldChangeZoom(previousZoom: previousZoom)) {
      cameraUpdate = CameraUpdate.newLatLngZoom(latLng, cameraFocusZoom);
    } else {
      cameraUpdate = CameraUpdate.newLatLng(latLng);
    }

    await _animateCamera(cameraUpdate);
  }

  Future<void> drawRoute({
    required List<LatLng> points,
    required bool animateCamera,
  }) async {
    final controller = await _getController();

    if (!mounted) return;

    await controller.addLine(
      LineOptions(
        geometry: points,
        lineColor: Colors.blue.toHexStringRGB(),
        lineWidth: 4,
      ),
    );
    if (!mounted) return;

    if (animateCamera) {
      await animateToRoute(points: points);
    }
  }

  Future<void> animateToRoute({
    required List<LatLng> points,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final cameraBounds = points.convertToBounds();

    final cameraUpdate = CameraUpdate.newLatLngBounds(
      cameraBounds,
      left: _routeDefaultPadding + padding.left,
      right: _routeDefaultPadding + padding.right,
      bottom: _routeDefaultPadding + padding.bottom,
      top: _routeDefaultPadding + padding.top,
    );

    await _animateCamera(cameraUpdate);
  }

  Future<void> setMapLanguage() async {
    final controller = await _getController();

    if (!mounted) return;

    await controller.setMapLanguage("de");
  }

  Future<void> fadeoutNotImportantAreas() async {
    final controller = await _getController();

    if (!mounted) return;

    const sourceId = "geojson_europe_mask_source_id";

    final geojson = await _createEuropaMaskGeojson();

    await controller.addSource(sourceId, geojson);

    // Use the same color like the background color of the theme
    final color = Colors.black.toHexStringRGB();

    final managerLayoutId = await _findFirstManagerLayoutId(controller);

    await controller.addLayer(
      sourceId,
      "geojson_europe_mask_layer_id",
      FillLayerProperties(
        fillColor: color,
        fillOpacity: 0.5,
      ),
      enableInteraction: false,
      belowLayerId: managerLayoutId,
    );
  }

  // endregion

  Future<MaplibreMapController> _getController() async {
    final controller = await _mapReadyCompleter.future;
    await _styleLoadedCompleter.future;

    return controller;
  }

  Future<GeojsonSourceProperties> _createEuropaMaskGeojson() async {
    final data = await DefaultAssetBundle.of(context)
        .loadString("assets/europeMask.geojson");

    final geoJson = (json.decode(data) as Map).cast<String, Object>();

    return GeojsonSourceProperties(data: geoJson);
  }

  /// The grey layer need to be below the manager, since we want to show
  /// all lines, icons, images above the grey layer and not below.
  Future<String> _findFirstManagerLayoutId(
    MaplibreMapController controller,
  ) async {
    final managerLayerIds = [
      ...controller.lineManager!.layerIds,
      ...controller.symbolManager!.layerIds,
      ...controller.circleManager!.layerIds,
      ...controller.fillManager!.layerIds,
      // We also want to show the city-names, countries and so on on top of the gray layer,
      // to improve the orientation of the user
      "place-village",
    ];

    final allLayerIds = await controller.getLayerIds();

    return allLayerIds
        .map((layerId) => layerId.toString())
        .firstWhere((layerId) => managerLayerIds.contains(layerId));
  }

  Future<void> _animateCamera(CameraUpdate cameraUpdate) async {
    final controller = await _getController();

    if (!mounted) return;

    await controller.animateCamera(
      cameraUpdate,
      duration: const Duration(milliseconds: 1500),
    );
  }

  Future<void> _removeSymbols() async {
    final controller = await _getController();

    if (!mounted) return;

    if (controller.symbols.isNotEmpty) {
      await controller.removeSymbols(controller.symbols);
    }

    _symbolMap.clear();
  }

  Future<void> _scheduleGeometryRedraw() async {
    _styleLoadedCompleter = Completer();
    await _styleLoadedCompleter.future;
    if (!mounted) return;

    await removeRoute();
    final route = widget.route;
    if (route != null) {
      await drawRoute(points: route, animateCamera: false);
    }

    final mapIcons = _symbolMap.values.toList();

    _cachedImages.clear();
    await _removeSymbols();

    for (final icon in mapIcons) {
      await drawIcon(icon, animateCamera: false);
    }
  }

  @visibleForTesting
  static bool shouldChangeZoom({double? previousZoom}) {
    const zoom = cameraFocusZoom;

    return previousZoom != null &&
        (previousZoom + acceptedZoomPadding < zoom ||
            previousZoom - acceptedZoomPadding > zoom);
  }

  Future<void> _addImageToCacheIfNeeded(
    MaplibreMapController controller, {
    required VectorMapIcon mapIcon,
  }) async {
    final icon = mapIcon.identifier;

    if (!_cachedImages.contains(icon)) {
      final imageBytes = await rootBundle.load(mapIcon.iconPath);

      if (!mounted) return;

      final byteArray = imageBytes.buffer.asUint8List();
      await controller.addImage(icon, byteArray);

      _cachedImages.add(icon);
    }
  }
}

extension on List<LatLng> {
  // https://stackoverflow.com/a/66545600/9277334
  LatLngBounds convertToBounds() {
    final route = this;

    assert(route.isNotEmpty);
    final firstLatLng = route.first;
    var s = firstLatLng.latitude,
        n = firstLatLng.latitude,
        w = firstLatLng.longitude,
        e = firstLatLng.longitude;
    for (var i = 1; i < route.length; i++) {
      final latlng = this[i];
      s = min(s, latlng.latitude);
      n = max(n, latlng.latitude);
      w = min(w, latlng.longitude);
      e = max(e, latlng.longitude);
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }
}

extension OnNextFrameExtension<T extends StatefulWidget> on State<T> {
  Future<void> onNextFrame(FutureOr<void> Function() method) {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        completer.complete(method());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      }
    });
    return completer.future;
  }
}

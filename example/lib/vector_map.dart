import 'dart:async';
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
  const VectorMap({super.key});

  @override
  State<VectorMap> createState() => VectorMapState();
}

class VectorMapState extends State<VectorMap> {
  @visibleForTesting
  static const cameraFocusZoom = 16.5;

  /// This value is used to check if the zoom needs to be adjusted during the [CameraUpdate] or not.
  /// The current zoom +- [acceptedZoomPadding] is fine and there is no need to change anything.
  @visibleForTesting
  static const acceptedZoomPadding = 1.0;

  final _styleLoadedCompleter = Completer<void>();
  final _mapReadyCompleter = Completer<MaplibreMapController>();

  /// The key is the created identifier by the [SymbolOptions]
  /// the value is the object from the user.
  final _symbolMap = <String, VectorMapIcon>{};

  /// There is no need to create the same image multiple times, that why we cache the identifier.
  final _cachedImages = <String>[];

  @override
  Widget build(BuildContext context) {
    // We need to change the id, otherwise the id is the same and the style is not correctly used
    const styleUrl =
        "https://api.maptiler.com/maps/3dd4d51b-ae78-4074-8b31-b47a49f1b5ce/style.json?key=kZ5xAKKbPzxo3GeJ2odT";

    return MaplibreMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(50.834060793873505, 4.340443996254663),
        zoom: 12,
      ),
      // ⚠️ MapBox styles are not supported! -> https://github.com/maplibre/flutter-maplibre-gl/issues/149
      styleString: styleUrl,
      compassEnabled: false,
      // We show an custom indicator for the current location, since we want some custom handling.
      myLocationEnabled: false,
      // We disable the different perspective, since the style doesn't
      // support that feature in 3d.
      // https://www.nextpit.com/forum/561686/how-to-use-google-maps-secret-gestures
      tiltGesturesEnabled: false,
      onMapClick: null,
      onMapCreated: (controller) async {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          _mapReadyCompleter.complete(controller);
        });
      },
      onStyleLoadedCallback: () async {
        // We are not using "completeOnce" here because we should never
        // run into the issue that this is already completed.
        // Every time we change the style we are creating a fresh completer
        // and we wait for the completer to finish.
        _styleLoadedCompleter.complete();

        _fadeoutNotImportantAreas();

        final controller = await _getController();

        if (!mounted) return;

        await controller.setMapLanguage("de");
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

  Future<void> drawIcon(VectorMapIcon mapIcon) async {
    final controller = await _getController();
    if (!mounted) return;

    await _addImageToCacheIfNeeded(controller, mapIcon: mapIcon);

    final symbol = await controller.addSymbol(
      SymbolOptions(
        geometry: mapIcon.latLng,
        iconImage: mapIcon.identifier,
      ),
    );

    _symbolMap[symbol.id] = mapIcon;

    final previousZoom = controller.cameraPosition?.zoom;

    final CameraUpdate cameraUpdate;

    if (_shouldChangeZoom(previousZoom: previousZoom)) {
      cameraUpdate =
          CameraUpdate.newLatLngZoom(mapIcon.latLng, cameraFocusZoom);
    } else {
      cameraUpdate = CameraUpdate.newLatLng(mapIcon.latLng);
    }

    await _animateCamera(cameraUpdate);
  }

  Future<void> _fadeoutNotImportantAreas() async {
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

  bool _shouldChangeZoom({double? previousZoom}) {
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

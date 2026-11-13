import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/app_data.dart';
import '../theme/washpro_theme.dart';

class LocationPickResult {
  LocationPickResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
    required this.line,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.building,
    required this.area,
    this.country = 'India',
    this.formattedAddress = '',
  });
  final double latitude;
  final double longitude;
  final String displayName;
  final String line;
  final String city;
  final String state;
  final String postalCode;
  final String building;
  final String area;
  final String country;
  final String formattedAddress;
}

/// OpenStreetMap location picker (flutter_map + Nominatim, rate-limited).
/// Coordinates always come from the map center / GPS — never from city name alone.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initial});
  final Addr? initial;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final mapController = MapController();
  final searchCtrl = TextEditingController();
  final nickCtrl = TextEditingController();
  final houseCtrl = TextEditingController();

  /// Fallback map view only — never saved as a service location unless the
  /// customer confirms after moving the pin / GPS.
  LatLng center = const LatLng(17.4486, 78.3908);
  bool pinConfirmedByUser = false;
  String addressLine = 'Move the map to select a location';
  String formattedAddress = '';
  String city = '';
  String state = '';
  String postal = '';
  String area = '';
  String building = '';
  String country = 'India';
  bool locating = false;
  bool resolving = false;
  bool showConfirmCard = false;
  String? error;
  Timer? _debounce;
  Timer? _searchDebounce;
  List<Map<String, dynamic>> suggestions = [];

  static const _ua = 'ZyloCustomer/1.2 (doorstep car wash; support@zylo.app)';
  static DateTime? _lastNominatim;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      nickCtrl.text = a.label;
      houseCtrl.text = a.slot == '—' ? '' : a.slot;
      if (a.hasCoordinates) {
        center = LatLng(a.latitude!, a.longitude!);
        pinConfirmedByUser = true;
        addressLine = a.line.isNotEmpty ? a.line : a.displayFormatted;
        formattedAddress = a.formattedAddress.isNotEmpty
            ? a.formattedAddress
            : a.displayFormatted;
        city = a.city;
        state = a.state;
        postal = a.postalCode;
        area = a.area;
        building = a.building;
        country = a.country.isNotEmpty ? a.country : 'India';
      } else if (a.line.isNotEmpty || a.displayFormatted.isNotEmpty) {
        // Legacy address without GPS — show text, require re-pin.
        addressLine = a.displayFormatted;
        formattedAddress = a.displayFormatted;
        city = a.city;
        state = a.state;
        postal = a.postalCode;
        area = a.area;
        building = a.building;
        error =
            'Location not verified. Move the pin to the exact service point.';
      }
    }
    // Skip auto-GPS when editing an already-pinned address — avoids laggy
    // reverse-geocode + GPS waits on ordinary edits.
    final hasPinned = widget.initial?.hasCoordinates == true;
    if (!hasPinned) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _goCurrent(silent: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    searchCtrl.dispose();
    nickCtrl.dispose();
    houseCtrl.dispose();
    mapController.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      setState(() => error =
          'Location permission denied. You can still pick on the map.');
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      setState(() => error =
          'Location permission is permanently denied. Open Settings to enable it, or pick on the map.');
      return false;
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() =>
          error = 'Location services are off. Enable GPS or pick on the map.');
      return false;
    }
    return true;
  }

  Future<void> _goCurrent({bool silent = false}) async {
    setState(() {
      locating = true;
      if (!silent) error = null;
    });
    try {
      if (!await _ensurePermission()) {
        setState(() => locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!isValidLatLng(pos.latitude, pos.longitude)) {
        setState(() => error = 'GPS returned invalid coordinates. Pick on the map.');
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        center = ll;
        pinConfirmedByUser = true;
      });
      mapController.move(ll, 16);
      await _reverse(ll);
    } on TimeoutException {
      if (mounted) {
        setState(() =>
            error = 'GPS timed out. Move the map pin or try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Could not get current location. Pick on the map instead.');
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _waitNominatim() async {
    final last = _lastNominatim;
    if (last != null) {
      final wait = const Duration(seconds: 1) - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    _lastNominatim = DateTime.now();
  }

  Future<void> _reverse(LatLng ll) async {
    setState(() => resolving = true);
    try {
      await _waitNominatim();
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${ll.latitude}&lon=${ll.longitude}&addressdetails=1');
      final res = await http.get(uri, headers: {'User-Agent': _ua});
      if (res.statusCode != 200) throw Exception('geocode ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};
      final road = [
        addr['house_number'],
        addr['road'],
        addr['neighbourhood'],
        addr['suburb']
      ]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
      final display = (data['display_name'] as String?)?.trim() ?? '';
      setState(() {
        formattedAddress = display.isNotEmpty
            ? display
            : (road.isNotEmpty
                ? road
                : '${ll.latitude.toStringAsFixed(6)}, ${ll.longitude.toStringAsFixed(6)}');
        addressLine = display.isNotEmpty
            ? display.split(',').take(3).join(',')
            : (road.isNotEmpty
                ? road
                : '${ll.latitude.toStringAsFixed(6)}, ${ll.longitude.toStringAsFixed(6)}');
        city = (addr['city'] ??
                addr['town'] ??
                addr['village'] ??
                addr['state_district'] ??
                '')
            .toString();
        state = (addr['state'] ?? '').toString();
        postal = (addr['postcode'] ?? '').toString();
        area = (addr['suburb'] ??
                addr['neighbourhood'] ??
                addr['county'] ??
                city)
            .toString();
        building = (addr['building'] ?? addr['house_number'] ?? '').toString();
        country = (addr['country'] ?? 'India').toString();
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          addressLine =
              '${ll.latitude.toStringAsFixed(6)}, ${ll.longitude.toStringAsFixed(6)}';
          formattedAddress = addressLine;
          error =
              'Could not resolve street address. Coordinates are still valid — you can confirm.';
        });
      }
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  void _onMapMoved(MapCamera cam, bool hasGesture) {
    if (!hasGesture) return;
    setState(() {
      center = cam.center;
      pinConfirmedByUser = true;
      showConfirmCard = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _reverse(cam.center);
    });
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        await _waitNominatim();
        final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/search?format=jsonv2&q=${Uri.encodeQueryComponent(q)}&addressdetails=1&limit=5&countrycodes=in');
        final res = await http.get(uri, headers: {'User-Agent': _ua});
        if (res.statusCode != 200 || !mounted) return;
        final list =
            (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        setState(() => suggestions = list);
      } catch (_) {
        if (mounted) {
          setState(() {
            suggestions = [];
            error = 'Address search failed. Check your connection.';
          });
        }
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> s) async {
    final lat = double.tryParse('${s['lat']}');
    final lon = double.tryParse('${s['lon']}');
    if (lat == null || lon == null || !isValidLatLng(lat, lon)) return;
    final ll = LatLng(lat, lon);
    setState(() {
      center = ll;
      pinConfirmedByUser = true;
      suggestions = [];
      searchCtrl.clear();
      showConfirmCard = false;
    });
    mapController.move(ll, 16);
    await _reverse(ll);
  }

  void _openConfirmCard() {
    if (!isValidLatLng(center.latitude, center.longitude)) {
      setState(() => error = 'Invalid map coordinates. Adjust the pin.');
      return;
    }
    if (!pinConfirmedByUser && widget.initial?.hasCoordinates != true) {
      setState(() => error =
          'Move the map pin or use current location before confirming.');
      return;
    }
    setState(() => showConfirmCard = true);
  }

  void _saveConfirmed() {
    if (!isValidLatLng(center.latitude, center.longitude)) {
      setState(() => error = 'Invalid coordinates — cannot save.');
      return;
    }
    final nick = nickCtrl.text.trim().isEmpty ? 'Address' : nickCtrl.text.trim();
    final house = houseCtrl.text.trim();
    final line = [
      if (house.isNotEmpty) house,
      if (building.isNotEmpty && building != house) building,
      addressLine,
    ].where((s) => s.trim().isNotEmpty).join(', ');
    final formatted = formattedAddress.trim().isNotEmpty
        ? formattedAddress.trim()
        : line;
    Navigator.pop(
      context,
      LocationPickResult(
        // Exact map-center / GPS values — not city geocode approximations.
        latitude: center.latitude,
        longitude: center.longitude,
        displayName: nick,
        line: line,
        city: city,
        state: state,
        postalCode: postal,
        building: house.isNotEmpty ? house : building,
        area: area.isNotEmpty ? area : city,
        country: country.isNotEmpty ? country : 'India',
        formattedAddress: formatted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            onPositionChanged: _onMapMoved,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.washpro.customer',
              maxNativeZoom: 19,
              errorTileCallback: (tile, error, stackTrace) {
                if (mounted && error != null) {
                  setState(() => error =
                      'Map tiles failed to load. Check your internet connection.');
                }
              },
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_on, size: 48, color: WpColors.primary),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(children: [
              Row(children: [
                Material(
                  color: context.wpCard,
                  borderRadius: BorderRadius.circular(14),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: context.wpCard,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 2,
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search address',
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ),
              ]),
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: context.wpCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.wpLine),
                  ),
                  child: Column(
                    children: suggestions
                        .map((s) => ListTile(
                              dense: true,
                              title: Text(
                                (s['display_name'] ?? '').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              onTap: () => _selectSuggestion(s),
                            ))
                        .toList(),
                  ),
                ),
            ]),
          ),
        ),
        Positioned(
          right: 16,
          bottom: showConfirmCard ? 420 : 300,
          child: FloatingActionButton.small(
            heroTag: 'loc',
            backgroundColor: context.wpCard,
            onPressed: locating ? null : () => _goCurrent(),
            child: locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.my_location, color: context.wpPrimary),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: context.wpCard,
            elevation: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: showConfirmCard
                    ? _buildConfirmCard(context)
                    : _buildPickerPanel(context),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPickerPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.place_outlined, color: context.wpPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              resolving ? 'Resolving address…' : addressLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        if (city.isNotEmpty || postal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 32),
            child: Text(
              [city, state, postal].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(color: context.wpMuted, fontSize: 12.5),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 32),
          child: Text(
            'Lat ${center.latitude.toStringAsFixed(6)} · Lng ${center.longitude.toStringAsFixed(6)}',
            style: TextStyle(color: context.wpMuted, fontSize: 11.5),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!,
                style: const TextStyle(color: WpColors.error, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: nickCtrl,
          decoration: const InputDecoration(
            labelText: 'Nickname (Home / Office)',
            prefixIcon: Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: houseCtrl,
          decoration: const InputDecoration(
            labelText: 'House / building / parking notes',
            prefixIcon: Icon(Icons.home_outlined),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: resolving ? null : _openConfirmCard,
          child: const Text('Confirm Location'),
        ),
      ],
    );
  }

  Widget _buildConfirmCard(BuildContext context) {
    final nick =
        nickCtrl.text.trim().isEmpty ? 'Address' : nickCtrl.text.trim();
    final house = houseCtrl.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Confirm service location',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: context.wpInk)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.wpMint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.wpLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nick, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                formattedAddress.isNotEmpty ? formattedAddress : addressLine,
                style: TextStyle(color: context.wpInk, height: 1.35),
              ),
              if (house.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Notes: $house',
                    style: TextStyle(color: context.wpMuted, fontSize: 12.5)),
              ],
              const SizedBox(height: 8),
              Text(
                'Latitude: ${center.latitude.toStringAsFixed(6)}\nLongitude: ${center.longitude.toStringAsFixed(6)}',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.wpPrimary,
                    fontSize: 13,
                    height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => showConfirmCard = false),
          child: const Text('Adjust location'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saveConfirmed,
          child: const Text('Confirm and Save'),
        ),
      ],
    );
  }
}

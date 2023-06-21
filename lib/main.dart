import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'place.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MedMap',
      theme: ThemeData(
        primarySwatch: Colors.lightBlue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Place> hospitals = [];
  late LatLng currentLocation;
  bool showSearchBar = false;

  @override
  void initState() {
    super.initState();
    fetchNearbyHospitals();
  }

  Future<Position> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are disabled
      return Future.error('Location services disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      // Permission denied forever, handle accordingly
      return Future.error('Location permission denied forever');
    }

    if (permission == LocationPermission.denied) {
      // Permission hasn't been granted, request permission
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        // Permission denied, handle accordingly
        return Future.error('Location permission denied');
      }
    }

    // Get the current location
    final Position position = await Geolocator.getCurrentPosition();
    currentLocation = LatLng(position.latitude, position.longitude);
    return position;
  }

  Future<List<Place>> searchNearbyHospitals(double latitude, double longitude) async {
    const String baseUrl = 'https://nominatim.openstreetmap.org/reverse';

    final String url = '$baseUrl?lat=$latitude&lon=$longitude&format=json';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final jsonResult = json.decode(response.body);
      final address = jsonResult['address'];
      final cityName = address['city'] ?? '';
      final stateName = address['state'] ?? '';

      final hospitalsUrl = 'https://nominatim.openstreetmap.org/search?q=hospital+in+$cityName+$stateName&format=json';
      final hospitalsResponse = await http.get(Uri.parse(hospitalsUrl));
      if (hospitalsResponse.statusCode == 200) {
        final hospitalsJson = json.decode(hospitalsResponse.body);
        final List<Place> places = [];
        hospitalsJson.forEach((result) {
          final name = result['display_name'] ?? '';
          final lat = double.tryParse(result['lat']) ?? 0.0;
          final lng = double.tryParse(result['lon']) ?? 0.0;
          final place = Place(name: name, latitude: lat, longitude: lng);
          places.add(place);
        });
        return places;
      } else {
        // Error occurred, handle accordingly
        return Future.error('API request failed');
      }
    } else {
      // Error occurred, handle accordingly
      return Future.error('API request failed');
    }
  }

  void fetchNearbyHospitals() async {
    try {
      Position currentPosition = await getCurrentPosition();
      if (currentPosition != null) {
        List<Place> nearbyHospitals = await searchNearbyHospitals(currentPosition.latitude, currentPosition.longitude);
        setState(() {
          hospitals = nearbyHospitals ?? [];
        });
      } else {
        // Location access denied or unavailable, handle accordingly
        print('Location access denied or unavailable');
      }
    } catch (e) {
      // Handle the error
      print('Error: $e');
    }
  }

  void viewHospitalDetails(Place hospital) {
    // Navigate to the map screen with hospital details
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MapScreen(currentLocation: currentLocation, hospital: hospital)),
    );
  }

  void searchPlace(String query) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/search?q=$query&format=json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final placesJson = json.decode(response.body);
        if (placesJson.isNotEmpty) {
          final place = placesJson.first;
          final lat = double.tryParse(place['lat']) ?? 0.0;
          final lng = double.tryParse(place['lon']) ?? 0.0;
          List<Place> nearbyHospitals = await searchNearbyHospitals(lat, lng);
          setState(() {
            hospitals = nearbyHospitals ?? [];
          });
        } else {
          // No places found, handle accordingly
          print('No places found');
        }
      } else {
        // Error occurred, handle accordingly
        print('API request failed');
      }
    } catch (e) {
      // Handle the error
      print('Error: $e');
    }
  }

  void toggleSearchBar() {
    setState(() {
      showSearchBar = !showSearchBar;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MedMap'),
        actions: [
          IconButton(onPressed: toggleSearchBar, icon: Icon(Icons.search_rounded))
        ],
      ),
      body: Column(
        children: [
          if (showSearchBar) // Only show the search bar if showSearchBar is true
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                onSubmitted: (value) => searchPlace(value),
                decoration: InputDecoration(
                  hintText: 'Search',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  suffixIcon: Icon(Icons.search),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: hospitals.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: GestureDetector(
                    onTap: () => viewHospitalDetails(hospitals[index]),
                    child: Card(
                      elevation: 2.0,
                      child: ListTile(
                        leading: Icon(Icons.local_hospital),
                        title: Text(hospitals[index].name),
                        subtitle: Text(
                          'Latitude: ${hospitals[index].latitude}, Longitude: ${hospitals[index].longitude}',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  final LatLng currentLocation;
  final Place hospital;

  MapScreen({required this.currentLocation, required this.hospital});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _getPolyline();
  }

  void _getPolyline() async {
    final String apiUrl =
        'https://api.openrouteservice.org/v2/directions/driving-car?api_key=5b3ce3597851110001cf624823ae44b816b64aa0b7501b3cedd6b6f6&start=${widget.currentLocation.longitude},${widget.currentLocation.latitude}&end=${widget.hospital.longitude},${widget.hospital.latitude}';

    final response = await http.get(Uri.parse(apiUrl));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['features'] != null && data['features'].isNotEmpty) {
        List<dynamic> coordinates =
        data['features'][0]['geometry']['coordinates'];
        List<LatLng> polylineCoordinates = coordinates
            .map((point) => LatLng(point[1], point[0]))
            .toList();

        setState(() {
          _polylineCoordinates = polylineCoordinates;
        });

        Polyline polyline = Polyline(
          polylineId: PolylineId("poly"),
          color: Colors.red,
          points: _polylineCoordinates,
          width: 12,
        );

        setState(() {
          _polylines.add(polyline);
        });
      } else {
        // No routes found, handle accordingly
        print('No routes found');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Map'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.hospital.latitude, widget.hospital.longitude),
              zoom: 17.0, // Adjust zoom level for a closer view
              bearing: 90.0, // Set bearing for tilt effect
              tilt: 60.0, // Set tilt angle for a 3D-like view
            ),
            markers: {
              Marker(
                markerId: MarkerId('hospital'),
                position: LatLng(widget.hospital.latitude, widget.hospital.longitude),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
            },
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),
          Positioned(
            top: 16.0,
            left: 16.0,
            right: 16.0,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Text(
                widget.hospital.name,
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

// Helper function to read JSON data from files
Future<dynamic> readJSONFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();
  return json.decode(content);
}

void main() async {
  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(_handleRequest);

  final server = await shelf_io.serve(handler, 'localhost', 3000);
  print('Server running on localhost:${server.port}');
}

Future<shelf.Response> _handleRequest(shelf.Request request) async {
  if (request.method == 'POST' && request.url.path == 'calculate-fuel') {
    final payload = await request.readAsString();
    final data = json.decode(payload);

    final routeId = data['routeId'];
    final vehicleId = data['vehicleId'];

    try {
      final routes = await readJSONFile('coordinates.json');
      final vehicles = await readJSONFile('vehicle_specs.json');

      if (routes is! List || vehicles is! List) {
        throw Exception("Invalid JSON structure. Expected a list.");
      }

      final route = routes.firstWhere((r) => r['id'] == routeId, orElse: () => null);
      final vehicle = vehicles.firstWhere((v) => v['id'] == vehicleId, orElse: () => null);

      if (route == null || vehicle == null) {
        return shelf.Response.notFound('Route or vehicle not found');
      }

      final distance = calculateDistance(route['origin'], route['destination']);
      final fuelData = calculateFuel(
        vehicle['mileage'],
        vehicle['vehicleWeight'],
        vehicle['passengerWeight'],
        vehicle['cargoWeight'],
        distance,
        vehicle['weather']
      );

      return shelf.Response.ok(json.encode(fuelData),
          headers: {'Content-Type': 'application/json'});
    } catch (error) {
      print('Error calculating fuel: $error');
      return shelf.Response.internalServerError(body: 'Error calculating fuel');
    }
  }

  return shelf.Response.notFound('Endpoint not found');
}

double calculateDistance(String origin, String destination) {
  final latLon1 = origin.split(',').map(double.parse).toList();
  final latLon2 = destination.split(',').map(double.parse).toList();

  final lat1 = latLon1[0];
  final lon1 = latLon1[1];
  final lat2 = latLon2[0];
  final lon2 = latLon2[1];

  const R = 6371; // Radius of Earth in kilometers
  final dLat = (lat2 - lat1) * (pi / 180);
  final dLon = (lon2 - lon1) * (pi / 180);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

// Fuel calculation with both fuel quantity in liters and cost
Map<String, dynamic> calculateFuel(int mileage, int vehicleWeight, int passengerWeight, int cargoWeight, double distance, String weather) {
  final totalWeight = vehicleWeight + passengerWeight + cargoWeight;
  final baseFuel = distance / mileage;  // Base fuel quantity in liters

  // Adjustments for weight
  double adjustedFuel = baseFuel * (1 + (totalWeight / 10000));

  // Weather adjustments
  const weatherMultipliers = {
    'clear': 1.0,
    'rainy': 1.1,
    'windy': 1.05,
    'snowy': 1.2
  };

  adjustedFuel *= weatherMultipliers[weather] ?? 1.0;  // Default to 1.0 if weather is not specified

  // Assuming an average fuel price for 2022
  const fuelPricePerLiter = 1.20; // In dollars per liter
  final fuelCost = adjustedFuel * fuelPricePerLiter;

  return {
    'fuelQuantity': adjustedFuel,
    'fuelCost': fuelCost
  };
}
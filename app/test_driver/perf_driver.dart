import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      for (final key in ['tabs', 'theme']) {
        final summary = driver.TimelineSummary.summarize(
            driver.Timeline.fromJson(data![key] as Map<String, dynamic>));
        await summary.writeTimelineToFile(key, pretty: true, includeSummary: true);
      }
    });

import 'package:http/http.dart' as http;

import '../models/class_model.dart';

import '../models/appointment_model.dart';

class GoogleSheetService {
  static Future<List<AppointmentModel>> getAppointments() async {
    const appointmentCsvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vT2irRooa5dp4VGfZrXxQNocmAzwi2hKBB8WCzoyqyljqsKhBUJecVWaxnCoIxEsKTf3jCJ9g8xutWi/pub?gid=1174084799&single=true&output=csv";

    final response = await http.get(
      Uri.parse(
        appointmentCsvUrl,
      ),
    );

    final rows = response.body.split(
      "\n",
    );

    final appointments = <AppointmentModel>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i].trim().split(
        ",",
      );

      if (row.length < 5) continue;

      appointments.add(
        AppointmentModel(
          day: row[0].trim(),
          appointmentName: row[1].trim(),
          coach: row[2].trim(),
          time: row[3].trim(),
          status: row[4].trim(),
        ),
      );
    }

    return appointments;
  }

  static const String csvUrl =
      "https://docs.google.com/spreadsheets/d/e/2PACX-1vT2irRooa5dp4VGfZrXxQNocmAzwi2hKBB8WCzoyqyljqsKhBUJecVWaxnCoIxEsKTf3jCJ9g8xutWi/pub?gid=0&single=true&output=csv";

  static Future<List<ClassModel>> getClasses() async {
    final response = await http.get(
      Uri.parse(
        csvUrl,
      ),
    );

    final rows = response.body.split(
      "\n",
    );

    final classes = <ClassModel>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i].trim().split(
        ",",
      );

      if (row.length < 10) continue;

      final occurrence =
          row.length > 10 ? row[10].trim() : 'weekly';
      final specificDate =
          row.length > 11 ? row[11].trim() : '';

      classes.add(
        ClassModel(
          day: row[0].trim(),
          mode: row[1].trim(),
          coach: row[2].trim(),
          location: row[3].trim(),
          groupSize: row[4].trim(),
          duration: row[5].trim(),
          detailLocation: row[6].trim(),
          startTime: row[7].trim(),
          type: row[8].trim(),
          image: row[9].trim(),
          occurrence: occurrence.isEmpty ? 'weekly' : occurrence,
          specificDate: specificDate.isEmpty ? null : specificDate,
        ),
      );
    }

    return classes;
  }
}

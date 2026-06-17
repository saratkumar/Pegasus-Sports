import 'package:flutter/material.dart';

import '../../models/appointment_model.dart';
import '../../services/google_sheet_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppointmentsScreen extends StatelessWidget {
  Future<void> createAppointmentBooking(
    BuildContext context,
    String appointmentId,
    String bookingDay,
    String bookingTime,
  ) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final existing = await FirebaseFirestore.instance
        .collection(
          "bookings",
        )
        .where(
          "userId",
          isEqualTo: userId,
        )
        .where(
          "className",
          isEqualTo: appointmentId,
        )
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            "Already Registered",
          ),
        ),
      );

      return;
    }

    await FirebaseFirestore
    .instance

    .collection(
      "bookings",
    )

    .add({

  "userId":

      userId,

  "className":

      appointmentId,

  "bookingType":

      "appointment",

  "bookingDay":

      bookingDay,

  "bookingTime":

      bookingTime,

  "createdAt":

      Timestamp.now(),

});

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(
        content: Text(
          "Appointment Booked",
        ),
      ),
    );
  }

  const AppointmentsScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Appointments",
        ),
      ),
      body: FutureBuilder<List<AppointmentModel>>(
        future: GoogleSheetService.getAppointments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No Appointments",
              ),
            );
          }

          final appointments = snapshot.data!;

          return ListView.builder(
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final item = appointments[index];

              final appointmentId = "${item.day}_"
                  "${item.appointmentName}_"
                  "${item.time}";

              return Card(
                margin: const EdgeInsets.all(
                  10,
                ),
                child: ListTile(
                  title: Text(
                    item.appointmentName,
                  ),
                  subtitle: Text(
                    "${item.coach}\n"
                    "${item.time}\n"
                    "${item.status}",
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      createAppointmentBooking(
                        context,
                        appointmentId,
                        item.day,
                        item.time,
                      );
                    },
                    child: const Text(
                      "Book",
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

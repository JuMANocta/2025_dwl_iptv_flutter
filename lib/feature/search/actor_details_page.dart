import 'package:flutter/material.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/models/person_model.dart';

class ActorDetailsPage extends StatelessWidget {
  final int personId;
  const ActorDetailsPage({super.key, required this.personId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: FutureBuilder<Person?>(
        future: TmdbService.instance.getPersonDetails(personId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(child: Text("Erreur : Fiche Acteur non trouvée.", style: TextStyle(color: Colors.red.shade400)));
          }

          final person = snapshot.data!;
          final profileUrl = TmdbService.getPosterUrl(person.profilePath, size: 'w342');

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280.0,
                pinned: true,
                backgroundColor: colorScheme.surface,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(person.name, style: const TextStyle(shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
                  centerTitle: false,
                  background: (profileUrl != null)
                      ? Image.network(profileUrl, fit: BoxFit.cover)
                      : Container(color: colorScheme.surfaceContainerHighest),
                ),
              ),

              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // BIOGRAPHIE
                        Text("Biographie", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                        Divider(color: colorScheme.outlineVariant),
                        Text(
                          person.biography ?? "Biographie indisponible.",
                          style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.5),
                        ),
                        const SizedBox(height: 32),

                        // FILMOGRAPHIE
                        Text("Filmographie (Rôles)", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                        Divider(color: colorScheme.outlineVariant),

                        // Liste des crédits
                        ...person.filmography.map((credit) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(credit.year?.toString() ?? 'N/A', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          title: Text(credit.title, style: TextStyle(color: colorScheme.onSurface)),
                          subtitle: Text("Rôle: ${credit.character ?? 'N/A'}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          trailing: Chip(
                            label: Text(credit.mediaType.toUpperCase(), style: const TextStyle(fontSize: 10)),
                            backgroundColor: credit.mediaType == 'movie' ? Colors.blue.withAlpha(51) : Colors.purple.withAlpha(51),
                          ),
                        ))
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
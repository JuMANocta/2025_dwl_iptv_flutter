import 'package:flutter/material.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/models/person_model.dart';

class ActorDetailsPage extends StatelessWidget {
  final int personId;
  const ActorDetailsPage({super.key, required this.personId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
                backgroundColor: Colors.black,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(person.name, style: const TextStyle(shadows: [Shadow(blurRadius: 5, color: Colors.black)])),
                  centerTitle: false,
                  background: (profileUrl != null)
                      ? Image.network(profileUrl, fit: BoxFit.cover)
                      : Container(color: Colors.grey.shade900),
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
                        Text("Biographie", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                        const Divider(color: Colors.white24),
                        Text(
                          person.biography ?? "Biographie indisponible.",
                          style: const TextStyle(color: Colors.grey, height: 1.5),
                        ),
                        const SizedBox(height: 32),

                        // FILMOGRAPHIE
                        Text("Filmographie (Rôles)", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                        const Divider(color: Colors.white24),

                        // Liste des crédits
                        ...person.filmography.map((credit) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(credit.year?.toString() ?? 'N/A', style: const TextStyle(color: Colors.grey)),
                          title: Text(credit.title, style: const TextStyle(color: Colors.white)),
                          subtitle: Text("Rôle: ${credit.character ?? 'N/A'}", style: const TextStyle(color: Colors.white70)),
                          trailing: Chip(
                            label: Text(credit.mediaType.toUpperCase(), style: const TextStyle(fontSize: 10)),
                            backgroundColor: credit.mediaType == 'movie' ? Colors.blue.withAlpha(51) : Colors.purple.withAlpha(51),
                          ),
                          // Optionnel : Ajouter un onTap pour ouvrir la fiche du film/série
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
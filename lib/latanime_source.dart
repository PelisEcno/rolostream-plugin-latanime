import 'package:rolostream_core/rolostream_core.dart' as core;
import 'latanime_plugin.dart' as raw;

/// Adaptador de [raw.LatanimePlugin] al contrato común de RoloStream.
/// Los modelos del plugin y los del core tienen los mismos campos: solo se reenvían.
class LatanimeSource implements core.SourcePlugin {
  LatanimeSource([raw.LatanimePlugin? plugin]) : _plugin = plugin ?? raw.LatanimePlugin();

  final raw.LatanimePlugin _plugin;

  @override
  String get id => 'latanime';

  @override
  String get name => 'Latanime';

  @override
  String? get iconAsset => null;

  @override
  String slugFromUrl(String url) {
    final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    return segs.isEmpty ? url : segs.last;
  }

  /// https://latanime.org/ver/ranma-2024-latino-episodio-29
  @override
  ({String slug, int numero})? parseEpisodeUrl(String url) {
    final m = RegExp(r'^(.*)-episodio-(\d+)$').firstMatch(slugFromUrl(url));
    if (m == null) return null;
    return (slug: m.group(1)!, numero: int.parse(m.group(2)!));
  }

  @override
  Future<List<core.AnimeResult>> search(String query) async => [
        for (final a in await _plugin.search(query))
          core.AnimeResult(nombre: a.nombre, url: a.url, imagen: a.imagen),
      ];

  @override
  Future<core.AnimeDetail> getAnime(String slug) async {
    final d = await _plugin.getAnime(slug);
    return core.AnimeDetail(
      titulo: d.titulo,
      sinopsis: d.sinopsis,
      imagen: d.imagen,
      estado: d.estado,
      generos: d.generos,
      episodios: [
        for (final e in d.episodios)
          core.Episode(numero: e.numero, url: e.url, titulo: e.titulo),
      ],
    );
  }

  @override
  Future<List<core.VideoServer>> getServers(String slug, int numero) async => [
        for (final s in await _plugin.getServers(slug, numero))
          core.VideoServer(nombre: s.nombre, url: s.url),
      ];

  @override
  Future<List<core.RecentEpisode>> getLatestEpisodes() async => [
        for (final e in await _plugin.getLatestEpisodes())
          core.RecentEpisode(titulo: e.titulo, url: e.url, imagen: e.imagen, fecha: e.fecha),
      ];

  @override
  Future<List<core.RecentSerie>> getRecentSeries() async => [
        for (final s in await _plugin.getRecentSeries())
          core.RecentSerie(titulo: s.titulo, url: s.url, imagen: s.imagen),
      ];

  @override
  Future<List<core.AiringAnime>> getAiringAnimes({int page = 1}) async => [
        for (final a in await _plugin.getAiringAnimes(page: page))
          core.AiringAnime(
              titulo: a.titulo, url: a.url, imagen: a.imagen, tipo: a.tipo, anio: a.anio),
      ];

  @override
  Future<List<core.FilterAnime>> getAnimesByFilter({
    String genero = 'false',
    String fecha = 'false',
    String letra = 'false',
    String categoria = 'false',
    int page = 1,
  }) async =>
      [
        for (final a in await _plugin.getAnimesByFilter(
          genero: genero,
          fecha: fecha,
          letra: letra,
          categoria: categoria,
          page: page,
        ))
          core.FilterAnime(
              titulo: a.titulo, url: a.url, imagen: a.imagen, tipo: a.tipo, anio: a.anio),
      ];

  @override
  core.FilterOptions get filterOptions => _filterOptions;
}

// Valores tal como los espera latanime.org/animes (sacados de sus <select>).
const _generos = <core.FilterOption>[
  core.FilterOption('accion', 'Acción'), core.FilterOption('aventura', 'Aventura'), core.FilterOption('carreras', 'Carreras'),
  core.FilterOption('ciencia-ficcion', 'Ciencia Ficción'), core.FilterOption('comedia', 'Comedia'), core.FilterOption('cyberpunk', 'Cyberpunk'),
  core.FilterOption('deportes', 'Deportes'), core.FilterOption('drama', 'Drama'), core.FilterOption('ecchi', 'Ecchi'), core.FilterOption('escolares', 'Escolares'),
  core.FilterOption('fantasia', 'Fantasía'), core.FilterOption('gore', 'Gore'), core.FilterOption('harem', 'Harem'), core.FilterOption('horror', 'Horror'),
  core.FilterOption('josei', 'Josei'), core.FilterOption('lucha', 'Lucha'), core.FilterOption('magia', 'Magia'), core.FilterOption('mecha', 'Mecha'),
  core.FilterOption('militar', 'Militar'), core.FilterOption('misterio', 'Misterio'), core.FilterOption('musica', 'Música'),
  core.FilterOption('parodias', 'Parodias'), core.FilterOption('psicologico', 'Psicológico'),
  core.FilterOption('recuerdos-de-la-vida', 'Recuerdos de la vida'), core.FilterOption('seinen', 'Seinen'), core.FilterOption('shojo', 'Shojo'),
  core.FilterOption('shonen', 'Shonen'), core.FilterOption('sobrenatural', 'Sobrenatural'), core.FilterOption('vampiros', 'Vampiros'),
  core.FilterOption('yaoi', 'Yaoi'), core.FilterOption('yuri', 'Yuri'), core.FilterOption('latino', 'Latino'), core.FilterOption('espacial', 'Espacial'),
  core.FilterOption('historico', 'Histórico'), core.FilterOption('samurai', 'Samurai'), core.FilterOption('artes-marciales', 'Artes Marciales'),
  core.FilterOption('demonios', 'Demonios'), core.FilterOption('romance', 'Romance'), core.FilterOption('dementia', 'Dementia'),
  core.FilterOption('policia', 'Policía'), core.FilterOption('castellano', 'Castellano'), core.FilterOption('historia-paralela', 'Historia paralela'),
  core.FilterOption('aenime', 'Aenime'), core.FilterOption('donghua', 'Donghua'), core.FilterOption('blu-ray', 'Blu-ray'),
  core.FilterOption('monogatari', 'Monogatari'), core.FilterOption('suspenso', 'Suspenso'), core.FilterOption('isekai', 'Isekai'),
];

final _anios = <core.FilterOption>[
  for (var y = 2026; y >= 1982; y--) core.FilterOption('$y', '$y'),
];

final _letras = <core.FilterOption>[
  const core.FilterOption('09', '0-9'),
  for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) core.FilterOption(c, c),
];

const _categorias = <core.FilterOption>[
  core.FilterOption('anime', 'Anime'), core.FilterOption('ova', 'Ova'), core.FilterOption('Película', 'Película'), core.FilterOption('especial', 'Especial'),
  core.FilterOption('corto', 'Corto'), core.FilterOption('ona', 'Ona'), core.FilterOption('donghua', 'Donghua'), core.FilterOption('sin-censura', 'Sin Censura'),
  core.FilterOption('preestreno', 'Preestreno'), core.FilterOption('pelicula-1080p', 'Película 1080p'), core.FilterOption('latino', 'Latino'),
  core.FilterOption('Película Latino', 'Película Latino'), core.FilterOption('castellano', 'Castellano'),
  core.FilterOption('Película Castellano', 'Película Castellano'), core.FilterOption('ova-latino', 'Ova Latino'),
  core.FilterOption('ova-castellano', 'Ova Castellano'), core.FilterOption('latino-sin-censura', 'Latino Sin Censura'),
  core.FilterOption('live-action', 'Live Action'), core.FilterOption('Cartoon', 'Cartoon'), core.FilterOption('catalan', 'Catalán'),
];

final _filterOptions = core.FilterOptions(
  generos: _generos,
  anios: _anios,
  letras: _letras,
  categorias: _categorias,
);

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;

// ============================================================
// MODELOS (idénticos a latanime_plugin)
// ============================================================

class AnimeResult {
  final String nombre;
  final String url;
  final String imagen;
  AnimeResult({required this.nombre, required this.url, required this.imagen});
}

class RecentEpisode {
  final String titulo;
  final String url;
  final String imagen;
  final String fecha;
  RecentEpisode({required this.titulo, required this.url, required this.imagen, required this.fecha});
}

class Episode {
  final int numero;
  final String url;
  final String titulo;
  Episode({required this.numero, required this.url, required this.titulo});
}

class AnimeDetail {
  final String titulo;
  final String sinopsis;
  final String imagen;
  final String estado;
  final List<String> generos;
  final List<Episode> episodios;
  AnimeDetail({
    required this.titulo,
    required this.sinopsis,
    required this.imagen,
    required this.estado,
    required this.generos,
    required this.episodios,
  });
}

class VideoServer {
  final String nombre;
  final String url;
  VideoServer({required this.nombre, required this.url});
}

class RecentSerie {
  final String titulo;
  final String url;
  final String imagen;
  RecentSerie({required this.titulo, required this.url, required this.imagen});
}

class AiringAnime {
  final String titulo;
  final String url;
  final String imagen;
  final String tipo;
  final String anio;
  AiringAnime({
    required this.titulo,
    required this.url,
    required this.imagen,
    required this.tipo,
    required this.anio,
  });
}

class FilterAnime {
  final String titulo;
  final String url;
  final String imagen;
  final String tipo;
  final String anio;
  FilterAnime({
    required this.titulo,
    required this.url,
    required this.imagen,
    required this.tipo,
    required this.anio,
  });
}

// ============================================================
// PLUGIN
// ============================================================

class AnimeAV1Plugin {
  static const String _baseUrl = 'https://animeav1.com';
  static const String _cdnUrl = 'https://cdn.animeav1.com';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

  late final Dio _dio;
  late final CookieJar _cookieJar;

  AnimeAV1Plugin() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  // ----------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------

  Map<String, dynamic>? _extractSveltekitData(String html) {
    final match = RegExp(
      r'data:\s*(\[null,[\s\S]*?\])\s*,\s*form:',
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!) as List;
      final third = decoded[2] as Map;
      return third['data'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _extractCatalogData(String html) {
    final match = RegExp(
      r'\(function\(a,b\)\{[\s\S]*?return\s*(\{type:"data",data:[\s\S]*?\})\s*\}\(\{\},\{\}\)\)',
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      return decoded['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  String _coverUrl(dynamic id) {
    if (id == null) return '';
    final s = id.toString();
    return s.isEmpty ? '' : '$_cdnUrl/covers/$s.jpg';
  }

  String _thumbnailUrl(dynamic episodeId) {
    if (episodeId == null) return '';
    final s = episodeId.toString();
    return s.isEmpty ? '' : '$_cdnUrl/thumbnails/$s.jpg';
  }

  String _mapStatus(dynamic status) {
    switch (status) {
      case 1:
        return 'En emisión';
      case 2:
        return 'Próximamente';
      default:
        return 'Finalizado';
    }
  }

  String _formatRelativeDate(String? iso) {
    if (iso == null) return '';
    try {
      final date = DateTime.parse(iso.replaceAll(' ', 'T'));
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'hace ${diff.inHours} horas';
      if (diff.inDays == 1) return 'hace un día';
      return 'hace ${diff.inDays} días';
    } catch (_) {
      return '';
    }
  }

  String _extractSlug(String input) {
    if (input.startsWith('http')) {
      final segments = Uri.parse(input).pathSegments;
      if (segments.isNotEmpty) return segments.last;
    }
    return input;
  }

  List<FilterAnime> _parseCatalogHtml(String html) {
    final doc = html_parser.parse(html);
    final animes = <FilterAnime>[];
    final articles = doc.querySelectorAll('article.group\\/item');
    for (final article in articles) {
      final imgTag = article.querySelector('figure img');
      if (imgTag == null) continue;
      final imagen = imgTag.attributes['src'] ?? '';
      final linkTag = article.querySelector('a[href*="/media/"]');
      if (linkTag == null) continue;
      final url = '$_baseUrl${linkTag.attributes['href'] ?? ''}';
      final h3 = article.querySelector('header h3');
      final titulo = h3?.text.trim() ?? '';
      final typeTag = article.querySelector('div.rounded.bg-line');
      final tipo = typeTag?.text.trim() ?? '';
      if (titulo.isNotEmpty && url.isNotEmpty) {
        animes.add(FilterAnime(
          titulo: titulo,
          url: url,
          imagen: imagen,
          tipo: tipo,
          anio: '',
        ));
      }
    }
    return animes;
  }

  // ----------------------------------------------------------
  // 1. BÚSQUEDA
  // ----------------------------------------------------------

  Future<List<AnimeResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final res = await _dio.post(
        '$_baseUrl/api/search',
        data: {'query': query},
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {
            'Accept': '*/*',
            'Origin': _baseUrl,
            'Referer': '$_baseUrl/catalogo?search=$query',
          },
        ),
      );
      final list = res.data as List;
      return list.map((e) {
        final slug = e['slug'] as String? ?? '';
        final id = e['id'];
        return AnimeResult(
          nombre: e['title'] as String? ?? '',
          url: '$_baseUrl/media/$slug',
          imagen: _coverUrl(id),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ----------------------------------------------------------
  // 2. DETALLE DEL ANIME
  // ----------------------------------------------------------

  Future<AnimeDetail> getAnime(String slug) async {
    final cleanSlug = _extractSlug(slug);
    final res = await _dio.get<String>(
      '$_baseUrl/media/$cleanSlug',
      options: Options(responseType: ResponseType.plain),
    );
    final json = _extractSveltekitData(res.data ?? '');
    if (json == null) throw Exception('No se pudo extraer JSON de $cleanSlug');

    final media = json['media'] as Map<String, dynamic>? ?? {};

    final episodes = <Episode>[];
    final eps = media['episodes'] as List? ?? [];
    for (final e in eps) {
      final num = e['number'] as int? ?? 0;
      episodes.add(Episode(
        numero: num,
        url: '$_baseUrl/media/$cleanSlug/$num',
        titulo: 'Episodio $num',
      ));
    }
    episodes.sort((a, b) => a.numero.compareTo(b.numero));

    final genres = <String>[];
    final g = media['genres'] as List? ?? [];
    for (final genre in g) {
      genres.add(genre['name'] as String? ?? '');
    }

    return AnimeDetail(
      titulo: media['title'] as String? ?? '',
      sinopsis: media['synopsis'] as String? ?? '',
      imagen: _coverUrl(media['id']),
      estado: _mapStatus(media['status']),
      generos: genres,
      episodios: episodes,
    );
  }

  // ----------------------------------------------------------
  // 3. SERVIDORES
  // ----------------------------------------------------------

  Future<List<VideoServer>> getServers(String slug, int numero) async {
    final cleanSlug = _extractSlug(slug);
    final res = await _dio.get<String>(
      '$_baseUrl/media/$cleanSlug/$numero',
      options: Options(responseType: ResponseType.plain),
    );
    final json = _extractSveltekitData(res.data ?? '');
    if (json == null) return [];

    final embeds = json['embeds'] as Map<String, dynamic>? ?? {};
    final servers = <VideoServer>[];

    final lang = embeds.containsKey('SUB') ? 'SUB' : 'DUB';
    final list = (embeds[lang] as List?) ?? [];

    for (final e in list) {
      final server = (e['server'] as String?)?.toLowerCase() ?? '';
      final url = e['url'] as String? ?? '';
      if (url.isEmpty || server.isEmpty) continue;
      servers.add(VideoServer(nombre: server, url: url));
    }

    return servers;
  }

  // ----------------------------------------------------------
  // 4. EPISODIOS RECIENTES
  // ----------------------------------------------------------

  Future<List<RecentEpisode>> getLatestEpisodes() async {
    final res = await _dio.get<String>(
      '$_baseUrl/',
      options: Options(responseType: ResponseType.plain),
    );
    final json = _extractSveltekitData(res.data ?? '');
    if (json == null) return [];

    final list = json['latestEpisodes'] as List? ?? [];
    final out = <RecentEpisode>[];
    for (final e in list) {
      final media = e['media'] as Map<String, dynamic>? ?? {};
      final slug = media['slug'] as String? ?? '';
      final number = e['number'] as int? ?? 0;
      out.add(RecentEpisode(
        titulo: media['title'] as String? ?? '',
        url: '$_baseUrl/media/$slug/$number',
        imagen: _thumbnailUrl(e['id']),
        fecha: _formatRelativeDate(e['publishedAt'] as String?),
      ));
    }
    return out;
  }

  // ----------------------------------------------------------
  // 5. SERIES RECIENTES
  // ----------------------------------------------------------

  Future<List<RecentSerie>> getRecentSeries() async {
    final res = await _dio.get<String>(
      '$_baseUrl/',
      options: Options(responseType: ResponseType.plain),
    );
    final json = _extractSveltekitData(res.data ?? '');
    if (json == null) return [];

    final list = json['latestMedia'] as List? ?? [];
    final out = <RecentSerie>[];
    for (final m in list) {
      final slug = m['slug'] as String? ?? '';
      out.add(RecentSerie(
        titulo: m['title'] as String? ?? '',
        url: '$_baseUrl/media/$slug',
        imagen: _coverUrl(m['id']),
      ));
    }
    return out;
  }

  // ----------------------------------------------------------
  // 6. ANIMES EN EMISIÓN
  // ----------------------------------------------------------

  Future<List<AiringAnime>> getAiringAnimes({int page = 1}) async {
    final uri = Uri.parse('$_baseUrl/catalogo').replace(
      queryParameters: {
        'status': 'emision',
        if (page > 1) 'page': page.toString(),
      },
    );

    final res = await _dio.get<String>(
      uri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    final html = res.data ?? '';

    final data = _extractCatalogData(html);
    if (data == null) return [];

    final results = data['results'] as List? ?? [];
    final animes = <AiringAnime>[];
    for (final m in results) {
      final slug = m['slug'] as String? ?? '';
      final category = m['category'] as Map<String, dynamic>?;
      animes.add(AiringAnime(
        titulo: m['title'] as String? ?? '',
        url: '$_baseUrl/media/$slug',
        imagen: _coverUrl(m['id']),
        tipo: category?['name'] as String? ?? '',
        anio: '',
      ));
    }
    return animes;
  }

  // ----------------------------------------------------------
  // 7. FILTROS DE CATÁLOGO
  // ----------------------------------------------------------

  Future<List<FilterAnime>> getAnimesByFilter({
    String genero = 'false',
    String fecha = 'false',
    String letra = 'false',
    String categoria = 'false',
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/catalogo').replace(
      queryParameters: {
        if (genero != 'false') 'genre': genero,
        if (fecha != 'false') 'minYear': fecha,
        if (fecha != 'false') 'maxYear': fecha,
        if (letra != 'false') 'letter': letra,
        if (categoria != 'false') 'category': categoria,
        if (page > 1) 'page': page.toString(),
      },
    );

    final res = await _dio.get<String>(
      uri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    final html = res.data ?? '';

    final data = _extractCatalogData(html);
    if (data != null) {
      final results = data['results'] as List? ?? [];
      final animes = <FilterAnime>[];
      for (final m in results) {
        final slug = m['slug'] as String? ?? '';
        final category = m['category'] as Map<String, dynamic>?;
        animes.add(FilterAnime(
          titulo: m['title'] as String? ?? '',
          url: '$_baseUrl/media/$slug',
          imagen: _coverUrl(m['id']),
          tipo: category?['name'] as String? ?? '',
          anio: '',
        ));
      }
      return animes;
    }

    return _parseCatalogHtml(html);
  }
}
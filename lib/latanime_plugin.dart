import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

// --- Modelos (para que el plugin sea independiente) ---
class AnimeResult {
  final String nombre;
  final String url;
  final String imagen;
  AnimeResult({required this.nombre, required this.url, required this.imagen});
  factory AnimeResult.fromJson(Map<String, dynamic> json) => AnimeResult(
    nombre: json['nombre'] ?? '',
    url: json['url'] ?? '',
    imagen: json['imagen'] ?? '',
  );
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
  AnimeDetail({required this.titulo, required this.sinopsis, required this.imagen, required this.estado, required this.generos, required this.episodios});
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
  final String tipo; // "Latino", "Castellano", etc.
  final String anio; // <-- CAMBIADO AQUÍ

  AiringAnime({
    required this.titulo,
    required this.url,
    required this.imagen,
    required this.tipo,
    required this.anio, // <-- CAMBIADO AQUÍ
  });
}

// --- Lógica del Plugin ---
class LatanimePlugin {
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';
  late final Dio _dio;
  late final CookieJar _cookieJar;
  String? _cachedToken;

  LatanimePlugin() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      headers: {'User-Agent': _userAgent, 'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8'},
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<String> _getToken() async {
    if (_cachedToken != null) return _cachedToken!;
    final res = await _dio.get<String>('https://latanime.org/', options: Options(responseType: ResponseType.plain));
    final match = RegExp(r'name="csrf-token" content="([^"]+)"').firstMatch(res.data ?? '');
    if (match == null) throw Exception('No se encontró el token CSRF');
    _cachedToken = match.group(1);
    return _cachedToken!;
  }

  Future<List<AnimeResult>> search(String query) async {
    if (query.length < 3) return [];
    final token = await _getToken();
    final res = await _dio.post(
      'https://latanime.org/buscar_ajax',
      data: {'_token': token, 'q': query},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
      ),
    );
    final dynamic parsed = res.data is String ? jsonDecode(res.data) : res.data;
    if (parsed is! List) return [];
    return parsed.map((e) => AnimeResult.fromJson(e)).toList();
  }

  Future<AnimeDetail> getAnime(String slug) async {
    final res = await _dio.get<String>('https://latanime.org/anime/$slug', options: Options(responseType: ResponseType.plain));
    final doc = html_parser.parse(res.data ?? '');
    
    final titulo = doc.querySelector('h2')?.text.trim() ?? '';
    final sinopsis = doc.querySelector('p.my-2.opacity-75')?.text.trim() ?? '';
    final imagen = doc.querySelector('img.img-fluid2')?.attributes['src'] ?? '';
    final estado = doc.querySelector('.btn-estado')?.text.trim() ?? '';
    final generos = doc.querySelectorAll('a[href*="/genero/"] .btn').map((e) => e.text.trim()).toList();
    
    final episodios = <Episode>[];
    for (var link in doc.querySelectorAll('a[href*="/ver/"]')) {
      final alt = link.querySelector('img')?.attributes['alt'] ?? '';
      final match = RegExp(r'capitulo (\d+)', caseSensitive: false).firstMatch(alt);
      if (match != null) {
        episodios.add(Episode(
          numero: int.parse(match.group(1)!),
          url: link.attributes['href'] ?? '',
          titulo: alt,
        ));
      }
    }
    episodios.sort((a, b) => a.numero.compareTo(b.numero));
    
    return AnimeDetail(titulo: titulo, sinopsis: sinopsis, imagen: imagen, estado: estado, generos: generos, episodios: episodios);
  }

  Future<List<VideoServer>> getServers(String slug, int numero) async {
    final res = await _dio.get<String>('https://latanime.org/ver/$slug-episodio-$numero', options: Options(responseType: ResponseType.plain));
    final doc = html_parser.parse(res.data ?? '');
    final servers = <VideoServer>[];
    for (var el in doc.querySelectorAll('a.play-video')) {
      final base64Str = el.attributes['data-player'];
      if (base64Str != null) {
        try {
          servers.add(VideoServer(nombre: el.text.trim(), url: utf8.decode(base64Decode(base64Str))));
        } catch (_) {}
      }
    }
    return servers;
  }

    Future<List<RecentEpisode>> getLatestEpisodes() async {
    // Obtenemos la página principal
    final res = await _dio.get<String>('https://latanime.org/', options: Options(responseType: ResponseType.plain));
    final doc = html_parser.parse(res.data ?? '');
    
    final recientes = <RecentEpisode>[];

    // En el HTML, los episodios recientes están dentro de un div con clase "info" y luego "h2"
    // Buscamos todos los enlaces que apunten a un episodio (/ver/)
    final items = doc.querySelectorAll('.row .col-6 a[href*="/ver/"]');
    
    for (var item in items) {
      final url = item.attributes['href'] ?? '';
      final imgTag = item.querySelector('img');
      final imagen = imgTag?.attributes['data-src'] ?? imgTag?.attributes['src'] ?? '';
      
      final h2 = item.querySelector('.info h2');
      final titulo = h2?.text.trim() ?? '';
      
      final spanFecha = item.querySelector('.span-tiempo');
      final fecha = spanFecha?.text.trim() ?? '';

      if (titulo.isNotEmpty && url.isNotEmpty) {
        recientes.add(RecentEpisode(
          titulo: titulo,
          url: url,
          imagen: imagen,
          fecha: fecha,
        ));
      }
    }
    
    return recientes;
  }

    Future<List<RecentSerie>> getRecentSeries() async {
    final res = await _dio.get<String>('https://latanime.org/', options: Options(responseType: ResponseType.plain));
    final doc = html_parser.parse(res.data ?? '');
    
    final recientes = <RecentSerie>[];

    // Buscamos los items que están dentro de la sección de "Series recientes"
    // En el HTML están en <li class="col mb-4 ficha_efecto"> ... </li>
    final items = doc.querySelectorAll('li.ficha_efecto');
    
    for (var item in items) {
      final a = item.querySelector('a');
      if (a == null) continue;
      
      final url = a.attributes['href'] ?? '';
      final imgTag = a.querySelector('img');
      // Latanime usa 'data-src' para lazy loading
      final imagen = imgTag?.attributes['data-src'] ?? imgTag?.attributes['src'] ?? '';
      
      final h3 = a.querySelector('h3');
      final titulo = h3?.text.trim() ?? '';

      if (titulo.isNotEmpty && url.isNotEmpty) {
        recientes.add(RecentSerie(
          titulo: titulo,
          url: url,
          imagen: imagen,
        ));
      }
    }
    
    return recientes;
  }

        Future<List<AiringAnime>> getAiringAnimes({int page = 1}) async {
    final url = page == 1
        ? 'https://latanime.org/emision'
        : 'https://latanime.org/emision?p=$page';

    final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
    final doc = html_parser.parse(res.data ?? '');

    final animes = <AiringAnime>[];

    final items = doc.querySelectorAll('.series');

    for (var item in items) {
      // Buscar el enlace ancestro (equivalente a .closest('a'))
      Element? a = item;
      while (a != null && a.localName != 'a') {
        a = a.parent;
      }
      if (a == null) continue;

      final linkUrl = a.attributes['href'] ?? '';
      final imgTag = item.querySelector('img');
      final imagen = imgTag?.attributes['src'] ?? '';

      final h3 = item.querySelector('h3');
      final titulo = h3?.text.trim() ?? '';

      final spanTipo = item.querySelector('span.opacity-75');
      final tipo = spanTipo?.text.trim() ?? '';

      String anio = '';
      final spans = item.querySelectorAll('span');
      for (var span in spans) {
        if (span.text.contains('20')) {
          anio = span.text.trim();
          break;
        }
      }

      if (titulo.isNotEmpty && linkUrl.isNotEmpty) {
        animes.add(AiringAnime(
          titulo: titulo,
          url: linkUrl,
          imagen: imagen,
          tipo: tipo,
          anio: anio,
        ));
      }
    }

    return animes;
  }
}
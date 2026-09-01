// ============================================================================
// The Field House — Live Wallpaper
// FieldHouseEngine.cs — motor de la app (Windows 10 / 11), en C#
// Versión: ver el archivo VERSION
//
// Reemplaza a Change-Wallpaper.ps1 (versión PowerShell) y al lanzador
// separado que existía en versiones intermedias de este proyecto (un .vbs
// o un FieldHouseLauncher.exe aparte). Este único binario, compilado con
// csc.exe (incluido de fábrica en Windows, sin instalar nada), reemplaza a
// los dos:
//   - No abre ninguna ventana de consola cuando lo dispara la Tarea
//     Programada (a diferencia de powershell.exe, que siempre crea una
//     consola al arrancar, sin importar -WindowStyle Hidden).
//   - Arranca en pocos milisegundos (no carga el runtime de PowerShell).
//   - Ya no necesita un lanzador intermedio: la propia Tarea Programada lo
//     ejecuta directo.
//
// RESTRICCIÓN DE COMPATIBILIDAD IMPORTANTE:
// Se compila con csc.exe de .NET Framework (v4.0.30319), que solo entiende
// hasta C# 5 y no trae System.Text.Json (ese paquete recién viene incluido
// de fábrica desde .NET Framework 4.7.2, y antes de eso requeriría NuGet,
// que no está disponible en una compilación de un solo archivo con
// csc.exe). Por eso, a diferencia de un C# "moderno":
//   - No hay pattern matching de switch expressions, ni "is not (a or b)",
//     ni target-typed new, ni required members.
//   - El parseo/escritura de JSON está hecho a mano (clase MiniJson más
//     abajo), en vez de System.Text.Json o Json.NET.
//   - Se usa HttpWebRequest en vez de HttpClient con extensiones JSON.
// Esto es intencional: mantiene el proyecto en un solo archivo, sin
// paquetes NuGet ni pasos de restore, para que Build-Engine.ps1 pueda
// compilarlo con una sola invocación a csc.exe durante la instalación.
//
// Es el equivalente funcional exacto de bin/change_wallpaper.sh (la versión
// Linux/XFCE del proyecto): cambia el fondo de pantalla de Windows según
// franjas horarias FIJAS del reloj (o, en ModoHorarios "auto", según la
// salida/puesta real del sol), y según el clima actual (nublado/lluvia) en
// amanecer, mediodía, atardecer o noche.
//
// Uso:
//   FieldHouseEngine.exe                Ejecución normal (la usa la tarea
//                                         horaria).
//   FieldHouseEngine.exe --reboot       Ejecución de inicio de sesión:
//                                         espera EsperaInicialSegundos y,
//                                         si la red no está lista,
//                                         reintenta la ubicación y el
//                                         clima hasta ReintentosClimaInicial
//                                         veces cada EsperaReintentoClima
//                                         segundos.
//   FieldHouseEngine.exe --dry-run      Simula la ejecución: muestra qué
//                                         fondo se aplicaría sin tocar el
//                                         fondo real, sin escribir logs ni
//                                         estado, y sin esperas. Se puede
//                                         combinar con --reboot.
//   FieldHouseEngine.exe --config       Modo interactivo por consola para
//                                         reconfigurar modo de horarios y
//                                         franjas horarias.
//                                         Reescribe config.json.
//   FieldHouseEngine.exe --version      Muestra la versión del programa.
//   FieldHouseEngine.exe --help         Muestra esta ayuda.
//
// No tiene dependencias externas más allá de .NET Framework (ya instalado
// de fábrica en Windows 10/11): usa HttpWebRequest para consultar las APIs
// de MET Norway (api.met.no, clima y horario solar) e ip-api.com (geolo-
// calización automática por IP), y la API Win32 SystemParametersInfo
// (P/Invoke) para aplicar el fondo. No hay transición de fundido en esta
// versión (a diferencia de la versión Linux con ImageMagick): Windows
// aplica el cambio de forma directa.
// ============================================================================

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace FieldHouse
{
    // ------------------------------------------------------------------
    // JSON MÍNIMO (sin dependencias externas)
    // ------------------------------------------------------------------
    // Parser y escritor de JSON muy simple, suficiente para lo que este
    // programa necesita: objetos planos de string/número/bool y arrays de
    // objetos (para leer las respuestas de las APIs de MET Norway e
    // ip-api.com). No pretende ser un parser JSON de propósito general,
    // pero sí soporta lo que esas respuestas pueden traer: números con
    // decimales, negativos, notación científica, y strings con unicode
    // escapado (\uXXXX).

    internal enum JsonTipo { Objeto, Arreglo, Texto, Numero, Booleano, Nulo }

    internal sealed class JsonValor
    {
        public JsonTipo Tipo;
        public Dictionary<string, JsonValor> Objeto;
        public List<JsonValor> Arreglo;
        public string Texto;
        public double Numero;
        public bool Booleano;

        public static JsonValor DeObjeto(Dictionary<string, JsonValor> o) { return new JsonValor { Tipo = JsonTipo.Objeto, Objeto = o }; }
        public static JsonValor DeTexto(string s) { return new JsonValor { Tipo = JsonTipo.Texto, Texto = s ?? "" }; }
        public static JsonValor DeNumero(double n) { return new JsonValor { Tipo = JsonTipo.Numero, Numero = n }; }

        public JsonValor Obtener(string clave)
        {
            if (Tipo != JsonTipo.Objeto || Objeto == null) return null;
            JsonValor v;
            return Objeto.TryGetValue(clave, out v) ? v : null;
        }

        public string ComoTexto(string porDefecto)
        {
            return (Tipo == JsonTipo.Texto && Texto != null) ? Texto : porDefecto;
        }

        public long ComoEntero(long porDefecto)
        {
            return (Tipo == JsonTipo.Numero) ? (long)Numero : porDefecto;
        }

        public double ComoDecimal(double porDefecto)
        {
            return (Tipo == JsonTipo.Numero) ? Numero : porDefecto;
        }
    }

    /// <summary>Parser JSON de un solo paso sobre una cadena, a mano.</summary>
    internal static class MiniJson
    {
        public static JsonValor Parsear(string texto)
        {
            int pos = 0;
            JsonValor resultado = ParsearValor(texto, ref pos);
            return resultado;
        }

        private static JsonValor ParsearValor(string s, ref int pos)
        {
            SaltarEspacios(s, ref pos);
            if (pos >= s.Length) throw new FormatException("JSON incompleto.");

            char c = s[pos];
            if (c == '{') return ParsearObjeto(s, ref pos);
            if (c == '[') return ParsearArreglo(s, ref pos);
            if (c == '"') return JsonValor.DeTexto(ParsearCadena(s, ref pos));
            if (c == 't' || c == 'f') return ParsearBooleano(s, ref pos);
            if (c == 'n') { pos += 4; return new JsonValor { Tipo = JsonTipo.Nulo }; }
            return ParsearNumero(s, ref pos);
        }

        private static JsonValor ParsearObjeto(string s, ref int pos)
        {
            var dict = new Dictionary<string, JsonValor>();
            pos++; // '{'
            SaltarEspacios(s, ref pos);
            if (pos < s.Length && s[pos] == '}') { pos++; return JsonValor.DeObjeto(dict); }

            while (true)
            {
                SaltarEspacios(s, ref pos);
                string clave = ParsearCadena(s, ref pos);
                SaltarEspacios(s, ref pos);
                pos++; // ':'
                JsonValor valor = ParsearValor(s, ref pos);
                dict[clave] = valor;
                SaltarEspacios(s, ref pos);
                if (pos < s.Length && s[pos] == ',') { pos++; continue; }
                break;
            }
            SaltarEspacios(s, ref pos);
            pos++; // '}'
            return JsonValor.DeObjeto(dict);
        }

        private static JsonValor ParsearArreglo(string s, ref int pos)
        {
            var lista = new List<JsonValor>();
            pos++; // '['
            SaltarEspacios(s, ref pos);
            if (pos < s.Length && s[pos] == ']') { pos++; return new JsonValor { Tipo = JsonTipo.Arreglo, Arreglo = lista }; }

            while (true)
            {
                JsonValor valor = ParsearValor(s, ref pos);
                lista.Add(valor);
                SaltarEspacios(s, ref pos);
                if (pos < s.Length && s[pos] == ',') { pos++; continue; }
                break;
            }
            SaltarEspacios(s, ref pos);
            pos++; // ']'
            return new JsonValor { Tipo = JsonTipo.Arreglo, Arreglo = lista };
        }

        private static string ParsearCadena(string s, ref int pos)
        {
            pos++; // '"' inicial
            var sb = new StringBuilder();
            while (pos < s.Length && s[pos] != '"')
            {
                char c = s[pos];
                if (c == '\\' && pos + 1 < s.Length)
                {
                    pos++;
                    char esc = s[pos];
                    switch (esc)
                    {
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'n': sb.Append('\n'); break;
                        case 't': sb.Append('\t'); break;
                        case 'r': sb.Append('\r'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u':
                            string hex = s.Substring(pos + 1, 4);
                            sb.Append((char)Convert.ToInt32(hex, 16));
                            pos += 4;
                            break;
                        default: sb.Append(esc); break;
                    }
                    pos++;
                }
                else
                {
                    sb.Append(c);
                    pos++;
                }
            }
            pos++; // '"' final
            return sb.ToString();
        }

        private static JsonValor ParsearBooleano(string s, ref int pos)
        {
            if (s[pos] == 't') { pos += 4; return new JsonValor { Tipo = JsonTipo.Booleano, Booleano = true }; }
            pos += 5;
            return new JsonValor { Tipo = JsonTipo.Booleano, Booleano = false };
        }

        private static JsonValor ParsearNumero(string s, ref int pos)
        {
            int inicio = pos;
            while (pos < s.Length && (char.IsDigit(s[pos]) || s[pos] == '-' || s[pos] == '+' || s[pos] == '.' || s[pos] == 'e' || s[pos] == 'E'))
            {
                pos++;
            }
            string numTexto = s.Substring(inicio, pos - inicio);
            double numero = double.Parse(numTexto, CultureInfo.InvariantCulture);
            return JsonValor.DeNumero(numero);
        }

        private static void SaltarEspacios(string s, ref int pos)
        {
            while (pos < s.Length && char.IsWhiteSpace(s[pos])) pos++;
        }

        /// <summary>
        /// Escribe un objeto plano (claves de configuración de esta app)
        /// como JSON indentado y legible, a partir de una lista ordenada
        /// de pares clave/valor. No necesita ser genérico: FieldHouseConfig
        /// es la única clase que este programa serializa.
        /// </summary>
        public static string EscribirObjeto(List<KeyValuePair<string, object>> pares)
        {
            var sb = new StringBuilder();
            sb.Append("{\r\n");
            for (int i = 0; i < pares.Count; i++)
            {
                var par = pares[i];
                sb.Append("  \"").Append(par.Key).Append("\": ");
                object valor = par.Value;
                if (valor is string)
                {
                    sb.Append('"').Append(EscaparCadena((string)valor)).Append('"');
                }
                else if (valor is bool)
                {
                    sb.Append((bool)valor ? "true" : "false");
                }
                else
                {
                    sb.Append(Convert.ToString(valor, CultureInfo.InvariantCulture));
                }
                if (i < pares.Count - 1) sb.Append(',');
                sb.Append("\r\n");
            }
            sb.Append("}");
            return sb.ToString();
        }

        private static string EscaparCadena(string s)
        {
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }

    /// <summary>
    /// Configuración editable por el usuario (franjas horarias, transición,
    /// etc). Vive en config.json, separada del binario para que el usuario
    /// no tenga que recompilar nada si quiere ajustar un valor a mano. Los
    /// nombres de las propiedades siguen usando el mismo formato en
    /// español que la versión PowerShell, para que un config.json de una
    /// instalación previa siga siendo válido sin migración.
    /// </summary>
    internal sealed class FieldHouseConfig
    {
        public string CarpetaFondos = "";
        public string ModoHorarios = "fijo";
        public string HoraInicioAmanecer = "06:00";
        public string HoraInicioMediodia = "10:00";
        public string HoraInicioAtardecer = "15:00";
        public string HoraInicioNoche = "20:00";
        public int EsperaInicialSegundos = 15;
        public int ReintentosClimaInicial = 3;
        public int EsperaReintentoClima = 60;
        public int TtlCacheClima = 600;
        public long MaxLogBytes = 1048576;

        /// <summary>
        /// Claves numéricas que vinieron explícitas en el config.json
        /// leído (independientemente de su valor). Necesario porque un
        /// campo en 0 es un valor legítimo para varias de estas claves
        /// (por ejemplo TtlCacheClima: 0 para desactivar la caché de
        /// clima), así que FusionarConDefaults no puede usar "> 0" como
        /// señal de "¿está seteado?": eso pisaría un 0 explícito con el
        /// valor por defecto. Queda vacío si el objeto no vino de JSON
        /// (instancia "en blanco" creada a mano).
        /// </summary>
        public HashSet<string> ClavesNumericasPresentes = new HashSet<string>();

        public static FieldHouseConfig DesdeJson(JsonValor raiz)
        {
            var c = new FieldHouseConfig();
            if (raiz == null || raiz.Tipo != JsonTipo.Objeto) return c;

            c.CarpetaFondos = ObtenerTexto(raiz, "CarpetaFondos", c.CarpetaFondos);
            c.ModoHorarios = ObtenerTexto(raiz, "ModoHorarios", c.ModoHorarios);
            c.HoraInicioAmanecer = ObtenerTexto(raiz, "HoraInicioAmanecer", c.HoraInicioAmanecer);
            c.HoraInicioMediodia = ObtenerTexto(raiz, "HoraInicioMediodia", c.HoraInicioMediodia);
            c.HoraInicioAtardecer = ObtenerTexto(raiz, "HoraInicioAtardecer", c.HoraInicioAtardecer);
            c.HoraInicioNoche = ObtenerTexto(raiz, "HoraInicioNoche", c.HoraInicioNoche);
            c.EsperaInicialSegundos = (int)ObtenerEntero(raiz, "EsperaInicialSegundos", c.EsperaInicialSegundos);
            c.ReintentosClimaInicial = (int)ObtenerEntero(raiz, "ReintentosClimaInicial", c.ReintentosClimaInicial);
            c.EsperaReintentoClima = (int)ObtenerEntero(raiz, "EsperaReintentoClima", c.EsperaReintentoClima);
            c.TtlCacheClima = (int)ObtenerEntero(raiz, "TtlCacheClima", c.TtlCacheClima);
            c.MaxLogBytes = ObtenerEntero(raiz, "MaxLogBytes", c.MaxLogBytes);

            foreach (string clave in new[] { "EsperaInicialSegundos", "ReintentosClimaInicial", "EsperaReintentoClima", "TtlCacheClima", "MaxLogBytes" })
            {
                if (raiz.Obtener(clave) != null) c.ClavesNumericasPresentes.Add(clave);
            }

            return c;
        }

        private static string ObtenerTexto(JsonValor raiz, string clave, string porDefecto)
        {
            JsonValor v = raiz.Obtener(clave);
            return (v != null) ? v.ComoTexto(porDefecto) : porDefecto;
        }

        private static long ObtenerEntero(JsonValor raiz, string clave, long porDefecto)
        {
            JsonValor v = raiz.Obtener(clave);
            return (v != null) ? v.ComoEntero(porDefecto) : porDefecto;
        }

        public string AJson()
        {
            var pares = new List<KeyValuePair<string, object>>
            {
                new KeyValuePair<string, object>("CarpetaFondos", CarpetaFondos),
                new KeyValuePair<string, object>("ModoHorarios", ModoHorarios),
                new KeyValuePair<string, object>("HoraInicioAmanecer", HoraInicioAmanecer),
                new KeyValuePair<string, object>("HoraInicioMediodia", HoraInicioMediodia),
                new KeyValuePair<string, object>("HoraInicioAtardecer", HoraInicioAtardecer),
                new KeyValuePair<string, object>("HoraInicioNoche", HoraInicioNoche),
                new KeyValuePair<string, object>("EsperaInicialSegundos", EsperaInicialSegundos),
                new KeyValuePair<string, object>("ReintentosClimaInicial", ReintentosClimaInicial),
                new KeyValuePair<string, object>("EsperaReintentoClima", EsperaReintentoClima),
                new KeyValuePair<string, object>("TtlCacheClima", TtlCacheClima),
                new KeyValuePair<string, object>("MaxLogBytes", MaxLogBytes),
            };
            return MiniJson.EscribirObjeto(pares);
        }
    }

    internal sealed class CacheHorariosSol
    {
        public string Fecha = "";
        public int Amanecer;
        public int Mediodia;
        public int Atardecer;
        public int Noche;

        public string AJson()
        {
            var pares = new List<KeyValuePair<string, object>>
            {
                new KeyValuePair<string, object>("Fecha", Fecha),
                new KeyValuePair<string, object>("Amanecer", Amanecer),
                new KeyValuePair<string, object>("Mediodia", Mediodia),
                new KeyValuePair<string, object>("Atardecer", Atardecer),
                new KeyValuePair<string, object>("Noche", Noche),
            };
            return MiniJson.EscribirObjeto(pares);
        }

        public static CacheHorariosSol DesdeJson(JsonValor raiz)
        {
            if (raiz == null || raiz.Tipo != JsonTipo.Objeto) return null;
            var c = new CacheHorariosSol();
            JsonValor v;
            v = raiz.Obtener("Fecha"); c.Fecha = (v != null) ? v.ComoTexto("") : "";
            v = raiz.Obtener("Amanecer"); c.Amanecer = (v != null) ? (int)v.ComoEntero(0) : 0;
            v = raiz.Obtener("Mediodia"); c.Mediodia = (v != null) ? (int)v.ComoEntero(0) : 0;
            v = raiz.Obtener("Atardecer"); c.Atardecer = (v != null) ? (int)v.ComoEntero(0) : 0;
            v = raiz.Obtener("Noche"); c.Noche = (v != null) ? (int)v.ComoEntero(0) : 0;
            return c;
        }
    }

    internal sealed class CacheClima
    {
        public long Ts;
        public string Clima = "";

        public string AJson()
        {
            var pares = new List<KeyValuePair<string, object>>
            {
                new KeyValuePair<string, object>("Ts", Ts),
                new KeyValuePair<string, object>("Clima", Clima),
            };
            return MiniJson.EscribirObjeto(pares);
        }

        public static CacheClima DesdeJson(JsonValor raiz)
        {
            if (raiz == null || raiz.Tipo != JsonTipo.Objeto) return null;
            var c = new CacheClima();
            JsonValor v;
            v = raiz.Obtener("Ts"); c.Ts = (v != null) ? v.ComoEntero(0) : 0;
            v = raiz.Obtener("Clima"); c.Clima = (v != null) ? v.ComoTexto("") : "";
            return c;
        }
    }

    /// <summary>
    /// A diferencia de CacheClima/CacheHorariosSol (que expiran por TTL o
    /// por día), este caché NO tiene noción de expiración en sí mismo: es
    /// responsabilidad de ObtenerUbicacion() decidir cuándo usarlo (ver el
    /// comentario en esa función). Ts se guarda solo con fines informativos
    /// (para diagnóstico/logs), no para decidir si el caché sigue siendo
    /// válido.
    /// </summary>
    internal sealed class CacheUbicacion
    {
        public double Lat;
        public double Lon;
        public long Ts;

        public string AJson()
        {
            var pares = new List<KeyValuePair<string, object>>
            {
                new KeyValuePair<string, object>("Lat", Lat),
                new KeyValuePair<string, object>("Lon", Lon),
                new KeyValuePair<string, object>("Ts", Ts),
            };
            return MiniJson.EscribirObjeto(pares);
        }

        public static CacheUbicacion DesdeJson(JsonValor raiz)
        {
            if (raiz == null || raiz.Tipo != JsonTipo.Objeto) return null;
            var c = new CacheUbicacion();
            JsonValor v;
            v = raiz.Obtener("Lat"); c.Lat = (v != null) ? v.ComoDecimal(0) : 0;
            v = raiz.Obtener("Lon"); c.Lon = (v != null) ? v.ComoDecimal(0) : 0;
            v = raiz.Obtener("Ts"); c.Ts = (v != null) ? v.ComoEntero(0) : 0;
            return c;
        }
    }

    internal static class Program
    {
        // ------------------------------------------------------------------
        // RUTAS (convención estándar de Windows para datos de app de
        // usuario; mismas rutas que usaba la versión PowerShell, para que
        // una instalación existente siga funcionando sin migración).
        // ------------------------------------------------------------------

        private static readonly string DatosApp =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FieldHouse");

        private static readonly string ConfigDir =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FieldHouse");

        private static readonly string ConfigFile = Path.Combine(ConfigDir, "config.json");
        private static readonly string StateDir = Path.Combine(DatosApp, "state");
        private static readonly string LogFile = Path.Combine(StateDir, "log.txt");
        private static readonly string CacheClimaFile = Path.Combine(StateDir, "clima.cache.json");
        private static readonly string CacheHorariosFile = Path.Combine(StateDir, "horarios-sol.cache.json");
        private static readonly string CacheUbicacionFile = Path.Combine(StateDir, "ubicacion.cache.json");

        private static bool DryRun;
        private static bool Reboot;
        private static FieldHouseConfig Config = new FieldHouseConfig();
        private static Mutex MutexHandle;
        private static string AppVersion = "0.0.0";

        private static int Main(string[] args)
        {
            try { Console.OutputEncoding = new UTF8Encoding(false); }
            catch (IOException) { }
            string versionPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "VERSION");
            if (File.Exists(versionPath))
            {
                AppVersion = File.ReadAllText(versionPath).Trim();
            }

            try
            {
                return Ejecutar(args);
            }
            finally
            {
                if (MutexHandle != null)
                {
                    try { MutexHandle.ReleaseMutex(); }
                    catch (ApplicationException)
                    {
                        // El mutex puede no estar tomado si se salió antes
                        // del WaitOne (por ejemplo, error de configuración
                        // temprano); no es un error real.
                    }
                    MutexHandle.Close();
                }
            }
        }

        private static int Ejecutar(string[] args)
        {
            bool help = args.Any(a => a == "--help" || a == "-h" || a == "/?");
            bool version = args.Any(a => a == "--version" || a == "-v");
            bool configInteractivo = args.Any(a => a == "--config");
            DryRun = args.Any(a => a == "--dry-run");
            Reboot = args.Any(a => a == "--reboot");

            if (version)
            {
                Console.WriteLine("The Field House — Live Wallpaper v" + AppVersion + " (Windows)");
                return 0;
            }

            if (help)
            {
                MostrarAyuda();
                return 0;
            }

            if (configInteractivo)
            {
                return EjecutarConfiguracionInteractiva();
            }

            // ---------------------------------------------------------------
            // 0) Lock anti-concurrencia (solo en ejecución real)
            // ---------------------------------------------------------------
            // Cierra la puerta a que la tarea horaria y la de inicio de
            // sesión corran el programa a la vez y se pisen. Mutex con
            // nombre a nivel de sesión de Windows (sin el prefijo "Global\",
            // que requeriría privilegios elevados y no hace falta: alcanza
            // con coordinar ejecuciones del mismo usuario). El SO libera
            // mutexes abandonados automáticamente ante un cierre anormal.
            if (!DryRun)
            {
                Directory.CreateDirectory(StateDir);
                try
                {
                    MutexHandle = new Mutex(false, "FieldHouseWallpaperLock");
                }
                catch (Exception ex)
                {
                    EscribirLog("ERROR: no se pudo crear el mutex de sincronización (" + ex.Message + "). Se aborta esta ejecución.");
                    return 1;
                }

                bool tomado = MutexHandle.WaitOne(TimeSpan.FromSeconds(30));
                if (!tomado)
                {
                    EscribirLog("ERROR: no se pudo tomar el lock anti-concurrencia (otra ejecución sigue corriendo tras 30s). Se aborta esta ejecución.");
                    return 1;
                }
            }

            // ---------------------------------------------------------------
            // 0.1) Cargar configuración
            // ---------------------------------------------------------------

            if (!File.Exists(ConfigFile))
            {
                EscribirLog("ERROR: no se encontró el archivo de configuración en " + ConfigFile + ". ¿Corriste Install.ps1?");
                return 1;
            }

            FieldHouseConfig cargado;
            try
            {
                string json = File.ReadAllText(ConfigFile);
                JsonValor raiz = MiniJson.Parsear(json);
                cargado = FieldHouseConfig.DesdeJson(raiz);
            }
            catch (Exception ex)
            {
                EscribirLog("ERROR: no se pudo leer " + ConfigFile + " (" + ex.Message + ").");
                return 1;
            }

            // Se combina sobre los valores por defecto (en vez de usar el
            // objeto deserializado tal cual) para que cualquier clave
            // ausente en un config.json de una instalación vieja no rompa
            // la ejecución: simplemente conserva el valor por defecto.
            Config = FusionarConDefaults(cargado);

            string errorConfig;
            if (!ValidarConfiguracion(Config, out errorConfig))
            {
                EscribirLog("ERROR: " + errorConfig);
                return 1;
            }

            string fondoAmanecer = Path.Combine(Config.CarpetaFondos, "amanecer.jpg");
            string fondoMediodia = Path.Combine(Config.CarpetaFondos, "mediodia.jpg");
            string fondoAtardecer = Path.Combine(Config.CarpetaFondos, "tarde.jpg");
            string fondoNoche = Path.Combine(Config.CarpetaFondos, "noche.jpg");
            string fondoNubladoDia = Path.Combine(Config.CarpetaFondos, "nublado-dia.jpg");
            string fondoNubladoNoche = Path.Combine(Config.CarpetaFondos, "nublado-noche.jpg");
            string fondoLluviaDia = Path.Combine(Config.CarpetaFondos, "lluvia-dia.jpg");
            string fondoLluviaAtardecer = Path.Combine(Config.CarpetaFondos, "lluvia-atardecer.jpg");
            string fondoLluviaNoche = Path.Combine(Config.CarpetaFondos, "lluvia-noche.jpg");

            // ---------------------------------------------------------------
            // 0.2) Espera inicial (solo si se invoca con --reboot)
            // ---------------------------------------------------------------
            // Al iniciar sesión, el explorador y la red pueden tardar unos
            // segundos en estar listos. Solo se aplica con --reboot para no
            // demorar las ejecuciones periódicas normales. En --dry-run se
            // omite.

            if (Reboot && !DryRun)
            {
                Thread.Sleep(TimeSpan.FromSeconds(Config.EsperaInicialSegundos));
            }

            // ---------------------------------------------------------------
            // 0.3) Detectar la ubicación automáticamente (clima y sol)
            // ---------------------------------------------------------------
            // El usuario no configura ninguna ciudad ni coordenadas: en cada
            // ejecución se detecta la ubicación a partir de la IP pública
            // (ver ObtenerUbicacion). Al iniciar sesión (--reboot) la red
            // puede estar todavía levantándose, así que se reintenta hasta
            // ReintentosClimaInicial veces cada EsperaReintentoClima
            // segundos — el mismo mecanismo de espera que ya existía para
            // el clima, ahora también cubre la geolocalización porque ambas
            // dependen de que la red esté lista. Si tras los reintentos no
            // hay ubicación (ni siquiera una vieja en caché), ubicacion
            // queda null y las secciones siguientes se degradan al
            // comportamiento sin clima ni horarios por el sol.

            CacheUbicacion ubicacion = null;
            if (Reboot && !DryRun)
            {
                for (int intento = 1; intento <= Config.ReintentosClimaInicial; intento++)
                {
                    ubicacion = ObtenerUbicacion();
                    if (ubicacion != null) break;

                    if (intento < Config.ReintentosClimaInicial)
                    {
                        EscribirLog("Sin internet todavía para geolocalizar (intento " + intento + "/" + Config.ReintentosClimaInicial + "), se reintenta en " + Config.EsperaReintentoClima + "s.");
                        Thread.Sleep(TimeSpan.FromSeconds(Config.EsperaReintentoClima));
                    }
                }
            }
            else
            {
                ubicacion = ObtenerUbicacion();
            }

            if (ubicacion == null)
            {
                EscribirLog("AVISO: no se pudo detectar la ubicación (sin internet y sin una ubicación previa en caché); se usan horarios fijos y no hay clima disponible en esta ejecución.");
            }

            // ---------------------------------------------------------------
            // 1) Verificar que todas las imágenes de fondo existen
            // ---------------------------------------------------------------

            var fondosRequeridos = new[]
            {
                fondoAmanecer, fondoMediodia, fondoAtardecer, fondoNoche,
                fondoNubladoDia, fondoNubladoNoche,
                fondoLluviaDia, fondoLluviaAtardecer, fondoLluviaNoche
            };
            var faltantes = fondosRequeridos.Where(f => !File.Exists(f)).ToList();
            if (faltantes.Count > 0)
            {
                EscribirLog("ERROR: faltan " + faltantes.Count + " imagen(es) de fondo: " + string.Join(", ", faltantes.ToArray()));
                return 1;
            }

            // ---------------------------------------------------------------
            // 2) Determinar la franja horaria actual (horas fijas o "auto")
            // ---------------------------------------------------------------

            DateTime ahora = DateTime.Now;
            int ahoraMin = (ahora.Hour * 60) + ahora.Minute;

            int minAmanecer = ConvertirAMinutos(Config.HoraInicioAmanecer);
            int minMediodia = ConvertirAMinutos(Config.HoraInicioMediodia);
            int minAtardecer = ConvertirAMinutos(Config.HoraInicioAtardecer);
            int minNoche = ConvertirAMinutos(Config.HoraInicioNoche);

            if (Config.ModoHorarios == "auto" && ubicacion != null)
            {
                CacheHorariosSol horariosSol = ObtenerHorariosSol(ubicacion.Lat, ubicacion.Lon);
                if (horariosSol != null)
                {
                    minAmanecer = horariosSol.Amanecer;
                    minMediodia = horariosSol.Mediodia;
                    minAtardecer = horariosSol.Atardecer;
                    minNoche = horariosSol.Noche;
                    EscribirLog(
                        "Horarios según el sol: amanecer " + FormatearHora(minAmanecer) +
                        ", mediodía " + FormatearHora(minMediodia) +
                        ", atardecer " + FormatearHora(minAtardecer) +
                        ", noche " + FormatearHora(minNoche));
                }
                else
                {
                    EscribirLog("AVISO: no se pudo obtener la salida/puesta del sol; se usan los horarios fijos de config.json.");
                }
            }
            else if (Config.ModoHorarios == "auto")
            {
                EscribirLog("AVISO: ModoHorarios=auto pero no hay ubicación disponible; se usan los horarios fijos de config.json.");
            }

            // franjaClima indica qué fondo de nublado/lluvia corresponde
            // según la franja: "dia" (amanecer o mediodía), "atardecer" o
            // "noche".
            string fondo;
            string momento;
            string franjaClima;

            if (ahoraMin >= minAmanecer && ahoraMin < minMediodia)
            {
                fondo = fondoAmanecer; momento = "amanecer"; franjaClima = "dia";
            }
            else if (ahoraMin >= minMediodia && ahoraMin < minAtardecer)
            {
                fondo = fondoMediodia; momento = "mediodia"; franjaClima = "dia";
            }
            else if (ahoraMin >= minAtardecer && ahoraMin < minNoche)
            {
                fondo = fondoAtardecer; momento = "atardecer"; franjaClima = "atardecer";
            }
            else
            {
                fondo = fondoNoche; momento = "noche"; franjaClima = "noche";
            }

            // ---------------------------------------------------------------
            // 3) Consultar el clima actual y, si está nublado o llueve, usar
            //    el fondo correspondiente a la franja (día, atardecer o
            //    noche). Al iniciar sesión (--reboot) la red puede estar
            //    todavía levantándose, así que si la consulta falla se
            //    aplica ya el fondo base de la franja y se reintenta cada
            //    EsperaReintentoClima segundos, hasta ReintentosClimaInicial
            //    veces. (La ubicación en sí ya se resolvió en el paso 0.3;
            //    acá solo se reintenta la consulta de clima con esa
            //    ubicación.)
            // ---------------------------------------------------------------

            string clima = null;
            if (ubicacion == null)
            {
                // sin ubicación disponible: clima queda null, se usa el
                // fondo base.
            }
            else if (Reboot && !DryRun)
            {
                int intento = 1;
                while (intento <= Config.ReintentosClimaInicial)
                {
                    clima = ObtenerClima(ubicacion.Lat, ubicacion.Lon, Config.TtlCacheClima);
                    if (clima != null) break;

                    if (intento < Config.ReintentosClimaInicial)
                    {
                        EscribirLog("Sin internet todavía para el clima (intento " + intento + "/" + Config.ReintentosClimaInicial + "), se aplica el fondo base y se reintenta en " + Config.EsperaReintentoClima + "s.");
                        AplicarFondo(fondo);
                        Thread.Sleep(TimeSpan.FromSeconds(Config.EsperaReintentoClima));
                    }
                    intento++;
                }
            }
            else
            {
                clima = ObtenerClima(ubicacion.Lat, ubicacion.Lon, Config.TtlCacheClima);
            }

            if (clima == null)
            {
                EscribirLog("No se pudo consultar el clima, se usa el fondo base (" + momento + ")");
            }
            else if (ClimaCoincide(clima, "cloudy", "fair", "partlycloudy"))
            {
                if (franjaClima == "dia" || franjaClima == "atardecer")
                {
                    fondo = fondoNubladoDia; momento = "nublado de día (" + clima + ")";
                }
                else if (franjaClima == "noche")
                {
                    fondo = fondoNubladoNoche; momento = "nublado de noche (" + clima + ")";
                }
            }
            else if (ClimaCoincide(clima, "rain", "sleet", "snow", "thunder", "fog"))
            {
                if (franjaClima == "dia")
                {
                    fondo = fondoLluviaDia; momento = "lluvia de día (" + clima + ")";
                }
                else if (franjaClima == "atardecer")
                {
                    fondo = fondoLluviaAtardecer; momento = "lluvia de atardecer (" + clima + ")";
                }
                else if (franjaClima == "noche")
                {
                    fondo = fondoLluviaNoche; momento = "lluvia de noche (" + clima + ")";
                }
            }

            // ---------------------------------------------------------------
            // 4) Aplicar el fondo elegido
            // ---------------------------------------------------------------

            AplicarFondo(fondo);
            EscribirLog("Fondo aplicado: " + momento + " -> " + fondo);

            return 0;
        }

        // ------------------------------------------------------------------
        // AYUDA
        // ------------------------------------------------------------------

        private static void MostrarAyuda()
        {
            Console.WriteLine("The Field House — Live Wallpaper v" + AppVersion + " (Windows)");
            Console.WriteLine();
            Console.WriteLine("Cambia el fondo de pantalla de Windows según la franja horaria (amanecer,");
            Console.WriteLine("mediodía, atardecer, noche) y el clima actual (nublado/lluvia) de tu");
            Console.WriteLine("ubicación, detectada automáticamente por IP.");
            Console.WriteLine();
            Console.WriteLine("Uso:");
            Console.WriteLine("  FieldHouseEngine.exe [opciones]");
            Console.WriteLine();
            Console.WriteLine("Opciones:");
            Console.WriteLine("  (sin opciones)  Ejecución normal. La usa la tarea programada horaria.");
            Console.WriteLine("  --reboot        Ejecución de inicio de sesión: espera EsperaInicialSegundos");
            Console.WriteLine("                  y, si la red no está lista, reintenta la ubicación y el");
            Console.WriteLine("                  clima hasta ReintentosClimaInicial veces cada");
            Console.WriteLine("                  EsperaReintentoClima segundos.");
            Console.WriteLine("  --dry-run       Simula la ejecución: muestra qué fondo se aplicaría sin");
            Console.WriteLine("                  tocar el fondo real, sin escribir logs ni estado, y sin");
            Console.WriteLine("                  esperas. Se puede combinar con --reboot.");
            Console.WriteLine("  --config        Modo interactivo por consola para reconfigurar el modo");
            Console.WriteLine("                  de horarios y franjas horarias. Reescribe config.json.");
            Console.WriteLine("  --version       Muestra la versión del programa.");
            Console.WriteLine("  --help          Muestra esta ayuda.");
            Console.WriteLine();
            Console.WriteLine("La configuración (horarios) se lee de:");
            Console.WriteLine("  " + ConfigFile);
            Console.WriteLine();
            Console.WriteLine("Los logs se escriben en:");
            Console.WriteLine("  " + LogFile);
        }

        // ------------------------------------------------------------------
        // RECONFIGURACIÓN INTERACTIVA (--config)
        // ------------------------------------------------------------------
        // Modo de consola: se ejecuta a mano (nunca desde la Tarea
        // Programada), así que acá sí es correcto y esperable que abra una
        // ventana de consola normal — el usuario la abrió él mismo para
        // reconfigurar. Relee la configuración existente como punto de
        // partida, para que Enter en cada pregunta conserve el valor
        // actual.

        private static int EjecutarConfiguracionInteractiva()
        {
            Console.WriteLine();
            Console.WriteLine("=====================================================================");
            Console.WriteLine("       THE FIELD HOUSE — RECONFIGURACIÓN");
            Console.WriteLine("=====================================================================");
            Console.WriteLine();

            FieldHouseConfig actual = FusionarConDefaults(null);
            if (File.Exists(ConfigFile))
            {
                try
                {
                    string json = File.ReadAllText(ConfigFile);
                    JsonValor raiz = MiniJson.Parsear(json);
                    FieldHouseConfig cargado = FieldHouseConfig.DesdeJson(raiz);
                    actual = FusionarConDefaults(cargado);
                    Console.WriteLine("Se encontró una configuración existente en " + ConfigFile + ".");
                    Console.WriteLine("Presioná Enter en cualquier pregunta para conservar el valor actual.");
                    Console.WriteLine();
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Aviso: no se pudo leer la configuración existente (" + ex.Message + "). Se parte de los valores por defecto.");
                    Console.WriteLine();
                }
            }
            else
            {
                Console.WriteLine("No se encontró una configuración previa; se va a crear una nueva.");
                Console.WriteLine();
            }

            string modoHorarios = PreguntarTexto(
                "Modo de horarios: 'fijo' o 'auto' [" + actual.ModoHorarios + "]: ",
                actual.ModoHorarios,
                valor => valor == "fijo" || valor == "auto",
                "Debe ser 'fijo' o 'auto'.");

            string horaAmanecer = PreguntarHora("Hora de inicio de amanecer", actual.HoraInicioAmanecer);
            string horaMediodia = PreguntarHora("Hora de inicio de mediodía", actual.HoraInicioMediodia);
            string horaAtardecer = PreguntarHora("Hora de inicio de atardecer", actual.HoraInicioAtardecer);
            string horaNoche = PreguntarHora("Hora de inicio de noche", actual.HoraInicioNoche);

            actual.ModoHorarios = modoHorarios;
            actual.HoraInicioAmanecer = horaAmanecer;
            actual.HoraInicioMediodia = horaMediodia;
            actual.HoraInicioAtardecer = horaAtardecer;
            actual.HoraInicioNoche = horaNoche;

            if (string.IsNullOrEmpty(actual.CarpetaFondos))
            {
                actual.CarpetaFondos = Path.Combine(DatosApp, "fondos");
            }

            Directory.CreateDirectory(ConfigDir);
            File.WriteAllText(ConfigFile, actual.AJson(), Encoding.UTF8);

            Console.WriteLine();
            Console.WriteLine("Configuración guardada en " + ConfigFile);
            Console.WriteLine();
            return 0;
        }

        private static string PreguntarTexto(string prompt, string valorActual, Func<string, bool> esValido, string mensajeError)
        {
            while (true)
            {
                Console.Write(prompt);
                string entrada = Console.ReadLine();
                string valor = string.IsNullOrEmpty(entrada) ? valorActual : entrada.Trim();

                if (string.IsNullOrEmpty(valor))
                {
                    Console.WriteLine("No puede quedar vacío.");
                    continue;
                }

                if (!esValido(valor))
                {
                    Console.WriteLine("Valor inválido: '" + valor + "'. " + mensajeError);
                    continue;
                }

                return valor;
            }
        }

        private static string PreguntarHora(string etiqueta, string valorActual)
        {
            return PreguntarTexto(
                etiqueta + " (formato HH:MM 24h) [" + valorActual + "]: ",
                valorActual,
                valor => Regex.IsMatch(valor, @"^([01]?[0-9]|2[0-3]):[0-5][0-9]$"),
                "Debe estar en formato HH:MM de 24 horas. Ej: 06:00");
        }

        // ------------------------------------------------------------------
        // LOGGING
        // ------------------------------------------------------------------

        private static void EscribirLog(string mensaje)
        {
            if (DryRun)
            {
                Console.WriteLine("[dry-run] " + mensaje);
                return;
            }

            RotarLogSiHaceFalta();

            string linea = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " - " + mensaje;
            try
            {
                File.AppendAllText(LogFile, linea + Environment.NewLine, Encoding.UTF8);
            }
            catch (IOException)
            {
                // Si dos ejecuciones llegan a pisarse escribiendo el log en
                // el mismísimo instante (ventana muy angosta, ya que el
                // mutex normalmente lo evita), se prioriza no cortar la
                // ejecución por un fallo de logging.
            }
        }

        private static void RotarLogSiHaceFalta()
        {
            if (DryRun) return;
            if (!File.Exists(LogFile)) return;

            long maxBytes = (Config != null && Config.MaxLogBytes > 0) ? Config.MaxLogBytes : 1048576;
            long tamano = new FileInfo(LogFile).Length;

            if (tamano >= maxBytes)
            {
                string rotado = LogFile + ".1";
                try
                {
                    if (File.Exists(rotado)) File.Delete(rotado);
                    File.Move(LogFile, rotado);
                    string linea = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) +
                        " - Log superó " + maxBytes + " bytes; se rotó a " + rotado;
                    File.AppendAllText(LogFile, linea + Environment.NewLine, Encoding.UTF8);
                }
                catch (IOException)
                {
                    // No es crítico: si la rotación falla, se sigue
                    // escribiendo sobre el log actual.
                }
            }
        }

        // ------------------------------------------------------------------
        // UTILIDADES DE HORA
        // ------------------------------------------------------------------

        /// <summary>Convierte una hora en formato 24 horas ("HH:MM") a minutos desde medianoche.</summary>
        private static int ConvertirAMinutos(string hora)
        {
            string[] partes = hora.Split(':');
            return (int.Parse(partes[0], CultureInfo.InvariantCulture) * 60) + int.Parse(partes[1], CultureInfo.InvariantCulture);
        }

        /// <summary>
        /// Convierte minutos desde medianoche a formato HH:MM (solo para
        /// mensajes de log). Normaliza al rango [0, 1440) antes de
        /// formatear: minNoche puede superar 1440 cuando el atardecer real
        /// (en ModoHorarios="auto") ocurre después de las 22:00 y se le
        /// suman 2 horas (por ejemplo sunset 22:50 -> 1490 min). Sin
        /// normalizar, el mensaje mostraría "24:50" en vez de la hora real
        /// del día siguiente ("00:50"). Esto es solo para legibilidad: las
        /// comparaciones de franja horaria usan los minutos crudos y ya son
        /// correctas en ese caso.
        /// </summary>
        private static string FormatearHora(int minutos)
        {
            int min = minutos % 1440;
            if (min < 0) min += 1440;
            return (min / 60).ToString("00") + ":" + (min % 60).ToString("00");
        }

        // ------------------------------------------------------------------
        // CONFIGURACIÓN
        // ------------------------------------------------------------------

        /// <summary>
        /// Combina el config cargado del disco sobre los valores por
        /// defecto, preservando cualquier valor por defecto para una clave
        /// que el config.json cargado no traiga (por ejemplo, un
        /// config.json de una versión anterior sin alguna clave nueva).
        /// </summary>
        private static FieldHouseConfig FusionarConDefaults(FieldHouseConfig cargado)
        {
            var resultado = new FieldHouseConfig();
            resultado.CarpetaFondos = Path.Combine(DatosApp, "fondos");

            if (cargado == null) return resultado;

            if (!string.IsNullOrEmpty(cargado.CarpetaFondos)) resultado.CarpetaFondos = cargado.CarpetaFondos;
            if (!string.IsNullOrEmpty(cargado.ModoHorarios)) resultado.ModoHorarios = cargado.ModoHorarios;
            if (!string.IsNullOrEmpty(cargado.HoraInicioAmanecer)) resultado.HoraInicioAmanecer = cargado.HoraInicioAmanecer;
            if (!string.IsNullOrEmpty(cargado.HoraInicioMediodia)) resultado.HoraInicioMediodia = cargado.HoraInicioMediodia;
            if (!string.IsNullOrEmpty(cargado.HoraInicioAtardecer)) resultado.HoraInicioAtardecer = cargado.HoraInicioAtardecer;
            if (!string.IsNullOrEmpty(cargado.HoraInicioNoche)) resultado.HoraInicioNoche = cargado.HoraInicioNoche;

            // Se usa "¿vino la clave en el JSON?" en vez de "> 0" como
            // señal de "está seteado": un 0 explícito es un valor válido
            // (por ejemplo TtlCacheClima: 0 para desactivar la caché de
            // clima) y no debe pisarse con el valor por defecto. Un valor
            // negativo igual se acepta acá; ValidarConfiguracion es quien
            // lo rechaza más adelante con un mensaje de error claro.
            var claves = cargado.ClavesNumericasPresentes;
            if (claves.Contains("EsperaInicialSegundos")) resultado.EsperaInicialSegundos = cargado.EsperaInicialSegundos;
            if (claves.Contains("ReintentosClimaInicial")) resultado.ReintentosClimaInicial = cargado.ReintentosClimaInicial;
            if (claves.Contains("EsperaReintentoClima")) resultado.EsperaReintentoClima = cargado.EsperaReintentoClima;
            if (claves.Contains("TtlCacheClima")) resultado.TtlCacheClima = cargado.TtlCacheClima;
            if (claves.Contains("MaxLogBytes")) resultado.MaxLogBytes = cargado.MaxLogBytes;

            return resultado;
        }

        /// <summary>
        /// Valida los valores de configuración. Un valor inválido detiene
        /// la ejecución con un mensaje claro, porque aplicaría fondos
        /// erróneos o rompería las consultas de clima en silencio.
        /// </summary>
        private static bool ValidarConfiguracion(FieldHouseConfig config, out string error)
        {
            if (config.ModoHorarios != "fijo" && config.ModoHorarios != "auto")
            {
                error = "ModoHorarios inválido ('" + config.ModoHorarios + "'). Debe ser 'fijo' (horarios fijos en config.json) o 'auto' (según la salida/puesta del sol).";
                return false;
            }

            var horaRegex = new Regex(@"^([01]?[0-9]|2[0-3]):[0-5][0-9]$");
            var horas = new[]
            {
                new[] { "HoraInicioAmanecer", config.HoraInicioAmanecer },
                new[] { "HoraInicioMediodia", config.HoraInicioMediodia },
                new[] { "HoraInicioAtardecer", config.HoraInicioAtardecer },
                new[] { "HoraInicioNoche", config.HoraInicioNoche },
            };
            foreach (var par in horas)
            {
                if (!horaRegex.IsMatch(par[1]))
                {
                    error = par[0] + " inválido ('" + par[1] + "'). Debe estar en formato HH:MM de 24 horas. Ej: 06:00";
                    return false;
                }
            }

            var numericos = new Dictionary<string, long>
            {
                { "EsperaInicialSegundos", config.EsperaInicialSegundos },
                { "ReintentosClimaInicial", config.ReintentosClimaInicial },
                { "EsperaReintentoClima", config.EsperaReintentoClima },
                { "TtlCacheClima", config.TtlCacheClima },
                { "MaxLogBytes", config.MaxLogBytes },
            };
            foreach (var par in numericos)
            {
                if (par.Value < 0)
                {
                    error = par.Key + " inválido ('" + par.Value + "'). Debe ser un entero >= 0.";
                    return false;
                }
            }

            if (!Directory.Exists(config.CarpetaFondos))
            {
                error = "CarpetaFondos no es un directorio válido ('" + config.CarpetaFondos + "'). Revisá el valor en " + ConfigFile + ".";
                return false;
            }

            error = "";
            return true;
        }

        // ------------------------------------------------------------------
        // UBICACIÓN (autodetección por IP, sin configuración del usuario)
        // ------------------------------------------------------------------

        /// <summary>
        /// Detecta automáticamente la latitud/longitud del usuario a partir
        /// de su IP pública, usando ip-api.com (gratuito, sin API key, sin
        /// que el usuario tenga que configurar nada).
        ///
        /// A diferencia de ObtenerClima/ObtenerHorariosSol (que cachean por
        /// TTL/día y devuelven null como único valor de "no disponible"),
        /// acá el caché NO expira por tiempo: si ip-api.com no responde, se
        /// sigue usando la última ubicación conocida sin importar su
        /// antigüedad, en vez de degradar a "sin ubicación". Esto es
        /// intencional: una notebook normalmente no cambia de ciudad de un
        /// día para el otro, así que una ubicación de hace unos días sigue
        /// siendo mucho más útil que no tener ninguna. El caché solo se
        /// actualiza cuando la consulta realmente tiene éxito.
        ///
        /// Devuelve null SOLO si nunca hubo una geolocalización exitosa
        /// (sin caché previo) y la consulta actual también falla — es
        /// decir, en una instalación nueva sin conectividad. En ese caso el
        /// llamador degrada al comportamiento sin clima ni horarios por el
        /// sol (fondo base + horarios fijos), igual que ante cualquier otro
        /// fallo de red.
        /// </summary>
        private static CacheUbicacion ObtenerUbicacion()
        {
            try
            {
                string url = "http://ip-api.com/json/?fields=status,lat,lon";
                string respuesta = DescargarTexto(url, 6000);
                JsonValor raiz = MiniJson.Parsear(respuesta);

                JsonValor status = raiz.Obtener("status");
                string statusTexto = (status != null) ? status.ComoTexto("") : "";

                if (statusTexto == "success")
                {
                    JsonValor latValor = raiz.Obtener("lat");
                    JsonValor lonValor = raiz.Obtener("lon");
                    if (latValor != null && lonValor != null && latValor.Tipo == JsonTipo.Numero && lonValor.Tipo == JsonTipo.Numero)
                    {
                        var ubicacion = new CacheUbicacion();
                        ubicacion.Lat = latValor.ComoDecimal(0);
                        ubicacion.Lon = lonValor.ComoDecimal(0);
                        ubicacion.Ts = ObtenerUnixTime();

                        if (!DryRun)
                        {
                            try
                            {
                                File.WriteAllText(CacheUbicacionFile, ubicacion.AJson(), Encoding.UTF8);
                            }
                            catch (IOException)
                            {
                                EscribirLog("AVISO: no se pudo guardar el caché de ubicación en " + CacheUbicacionFile + ".");
                            }
                        }

                        return ubicacion;
                    }
                }
            }
            catch (Exception)
            {
                // Sin red, timeout, respuesta inesperada: se cae al caché
                // de abajo, sin importar el motivo puntual del fallo.
            }

            // ip-api.com no respondió o dio una respuesta inválida: se cae
            // a la última ubicación conocida, si existe, sin importar su
            // antigüedad.
            if (File.Exists(CacheUbicacionFile))
            {
                try
                {
                    string jsonCache = File.ReadAllText(CacheUbicacionFile);
                    JsonValor raizCache = MiniJson.Parsear(jsonCache);
                    return CacheUbicacion.DesdeJson(raizCache);
                }
                catch (Exception)
                {
                    // Caché corrupto o ilegible: no hay ubicación disponible.
                }
            }

            return null;
        }

        // ------------------------------------------------------------------
        // HORARIOS SEGÚN EL SOL (ModoHorarios = "auto")
        // ------------------------------------------------------------------

        /// <summary>
        /// Consulta la salida y puesta del sol en las coordenadas dadas
        /// usando la API oficial Sunrise 3.0 de MET Norway (api.met.no),
        /// que devuelve directamente la hora local (con su offset horario
        /// ya aplicado, sin que haga falta convertir de UTC a mano).
        /// Devuelve minutos desde medianoche para amanecer, mediodía
        /// (punto medio entre amanecer y atardecer), atardecer y noche
        /// (atardecer + 2 horas). El resultado se guarda en un caché
        /// diario y se reutiliza durante el día, para no consultar la API
        /// a cada ejecución horaria. Devuelve null si no se pudo obtener
        /// (sin internet, respuesta inesperada): el llamador usa entonces
        /// los horarios fijos.
        /// </summary>
        private static CacheHorariosSol ObtenerHorariosSol(double lat, double lon)
        {
            string fechaHoy = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

            if (File.Exists(CacheHorariosFile))
            {
                try
                {
                    string jsonCache = File.ReadAllText(CacheHorariosFile);
                    JsonValor raiz = MiniJson.Parsear(jsonCache);
                    CacheHorariosSol cache = CacheHorariosSol.DesdeJson(raiz);
                    if (cache != null && cache.Fecha == fechaHoy)
                    {
                        return cache;
                    }
                }
                catch (Exception)
                {
                    // Caché corrupto o ilegible: se ignora y se vuelve a
                    // consultar.
                }
            }

            string respuestaTexto;
            try
            {
                string url = "https://api.met.no/weatherapi/sunrise/3.0/sun?lat=" +
                    lat.ToString(CultureInfo.InvariantCulture) + "&lon=" +
                    lon.ToString(CultureInfo.InvariantCulture) + "&date=" + fechaHoy;
                respuestaTexto = DescargarTexto(url, 6000);
            }
            catch (Exception)
            {
                return null;
            }

            string salida = null;
            string puesta = null;
            try
            {
                JsonValor raiz = MiniJson.Parsear(respuestaTexto);
                JsonValor properties = raiz.Obtener("properties");
                if (properties != null && properties.Tipo == JsonTipo.Objeto)
                {
                    JsonValor sunrise = properties.Obtener("sunrise");
                    JsonValor sunset = properties.Obtener("sunset");
                    JsonValor sunriseTime = (sunrise != null) ? sunrise.Obtener("time") : null;
                    JsonValor sunsetTime = (sunset != null) ? sunset.Obtener("time") : null;
                    salida = ExtraerHoraDeIso8601((sunriseTime != null) ? sunriseTime.ComoTexto(null) : null);
                    puesta = ExtraerHoraDeIso8601((sunsetTime != null) ? sunsetTime.ComoTexto(null) : null);
                }
            }
            catch (Exception)
            {
                return null;
            }

            if (string.IsNullOrEmpty(salida) || string.IsNullOrEmpty(puesta))
            {
                return null;
            }

            int horaAmanecer = ConvertirAMinutos(salida);
            int horaAtardecer = ConvertirAMinutos(puesta);
            int mediodia = (horaAmanecer + horaAtardecer) / 2;
            int noche = horaAtardecer + 120;

            var resultado = new CacheHorariosSol();
            resultado.Fecha = fechaHoy;
            resultado.Amanecer = horaAmanecer;
            resultado.Mediodia = mediodia;
            resultado.Atardecer = horaAtardecer;
            resultado.Noche = noche;

            if (!DryRun)
            {
                try
                {
                    File.WriteAllText(CacheHorariosFile, resultado.AJson(), Encoding.UTF8);
                }
                catch (IOException)
                {
                    EscribirLog("AVISO: no se pudo guardar el caché de horarios del sol en " + CacheHorariosFile + ".");
                }
            }

            return resultado;
        }

        /// <summary>
        /// Extrae la parte "HH:MM" de un timestamp ISO 8601 con offset de
        /// zona horaria local ya aplicado, como el que devuelven las APIs
        /// de MET Norway (ej: "2026-08-27T09:16:00+01:00" o
        /// "2026-08-27T09:16+01:00", el offset puede o no incluir
        /// segundos). Devuelve null si el formato no es el esperado.
        /// </summary>
        private static string ExtraerHoraDeIso8601(string iso)
        {
            if (string.IsNullOrEmpty(iso)) return null;
            Match m = Regex.Match(iso, @"T(\d{2}):(\d{2})");
            if (!m.Success) return null;
            return m.Groups[1].Value + ":" + m.Groups[2].Value;
        }

        // ------------------------------------------------------------------
        // CLIMA
        // ------------------------------------------------------------------

        /// <summary>
        /// Consulta la API oficial Locationforecast 2.0 (compact) de MET
        /// Norway una vez (con timeout corto) y devuelve el symbol_code del
        /// pronóstico más inmediato disponible, en minúscula (ej: "cloudy",
        /// "rainshowers_day", "fair_night"). Devuelve null si la consulta
        /// falla o si no se pudo extraer un symbol_code (sin internet,
        /// respuesta inesperada, etc). Guarda el resultado en un caché por
        /// <paramref name="ttlCache"/> segundos, para no molestar a la API
        /// con consultas redundantes (por ejemplo, cuando la tarea horaria y
        /// el login disparan casi en el mismo momento).
        /// </summary>
        private static string ObtenerClima(double lat, double lon, int ttlCache)
        {
            if (File.Exists(CacheClimaFile) && !DryRun)
            {
                try
                {
                    string jsonCache = File.ReadAllText(CacheClimaFile);
                    JsonValor raiz = MiniJson.Parsear(jsonCache);
                    CacheClima cache = CacheClima.DesdeJson(raiz);
                    long ahora = ObtenerUnixTime();
                    if (cache != null && (ahora - cache.Ts) < ttlCache)
                    {
                        return cache.Clima;
                    }
                }
                catch (Exception)
                {
                    // Caché corrupto: se ignora y se vuelve a consultar.
                }
            }

            string clima;
            try
            {
                string url = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" +
                    lat.ToString(CultureInfo.InvariantCulture) + "&lon=" +
                    lon.ToString(CultureInfo.InvariantCulture);
                string respuesta = DescargarTexto(url, 6000);
                clima = ExtraerSymbolCode(respuesta);
            }
            catch (Exception)
            {
                return null;
            }

            if (string.IsNullOrEmpty(clima))
            {
                return null;
            }

            if (!DryRun)
            {
                try
                {
                    var cache = new CacheClima();
                    cache.Ts = ObtenerUnixTime();
                    cache.Clima = clima;
                    File.WriteAllText(CacheClimaFile, cache.AJson(), Encoding.UTF8);
                }
                catch (IOException)
                {
                    EscribirLog("AVISO: no se pudo guardar el caché de clima en " + CacheClimaFile + ".");
                }
            }

            return clima;
        }

        /// <summary>
        /// Extrae el symbol_code del pronóstico más inmediato de una
        /// respuesta de Locationforecast 2.0 compact: el primer
        /// timeseries[0].data.next_1_hours.summary.symbol_code, o
        /// next_6_hours si next_1_hours no está presente (pasa en
        /// horizontes lejanos; no debería ocurrir para "ahora" pero por
        /// robustez se contempla igual). Devuelve null si no se pudo
        /// extraer.
        /// </summary>
        private static string ExtraerSymbolCode(string respuestaJson)
        {
            JsonValor raiz = MiniJson.Parsear(respuestaJson);
            JsonValor properties = raiz.Obtener("properties");
            if (properties == null || properties.Tipo != JsonTipo.Objeto) return null;

            JsonValor timeseries = properties.Obtener("timeseries");
            if (timeseries == null || timeseries.Tipo != JsonTipo.Arreglo || timeseries.Arreglo.Count == 0) return null;

            JsonValor data = timeseries.Arreglo[0].Obtener("data");
            if (data == null || data.Tipo != JsonTipo.Objeto) return null;

            string symbol = ExtraerSymbolCodeDeTramo(data, "next_1_hours");
            if (string.IsNullOrEmpty(symbol))
            {
                symbol = ExtraerSymbolCodeDeTramo(data, "next_6_hours");
            }

            return string.IsNullOrEmpty(symbol) ? null : symbol.ToLowerInvariant();
        }

        private static string ExtraerSymbolCodeDeTramo(JsonValor data, string nombreTramo)
        {
            JsonValor tramo = data.Obtener(nombreTramo);
            if (tramo == null || tramo.Tipo != JsonTipo.Objeto) return null;

            JsonValor summary = tramo.Obtener("summary");
            if (summary == null || summary.Tipo != JsonTipo.Objeto) return null;

            JsonValor symbolCode = summary.Obtener("symbol_code");
            return (symbolCode != null) ? symbolCode.ComoTexto(null) : null;
        }

        private static long ObtenerUnixTime()
        {
            return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
        }

        private static bool ClimaCoincide(string clima, params string[] palabrasClave)
        {
            foreach (string p in palabrasClave)
            {
                if (clima.IndexOf(p, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        /// <summary>
        /// Descarga el contenido de <paramref name="url"/> como texto
        /// (UTF-8) usando HttpWebRequest, con el timeout indicado en
        /// milisegundos. Se usa HttpWebRequest en vez de HttpClient porque
        /// este proyecto se compila con csc.exe sin referencias NuGet, y
        /// HttpWebRequest está disponible en System.dll (base de .NET
        /// Framework) sin nada adicional que referenciar.
        /// </summary>
        private static string DescargarTexto(string url, int timeoutMs)
        {
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "GET";
            request.Timeout = timeoutMs;
            request.ReadWriteTimeout = timeoutMs;
            // api.met.no exige un User-Agent que identifique la app y dé
            // alguna forma de contacto (403 si falta o es genérico); se usa
            // el mismo para toda descarga (incluida ip-api.com, que no lo
            // exige pero tampoco le molesta).
            request.UserAgent = "FieldHouse-LiveWallpaper/" + AppVersion + " (github.com/agustincomolli/field-house)";

            using (var response = (HttpWebResponse)request.GetResponse())
            using (var stream = response.GetResponseStream())
            using (var reader = new StreamReader(stream, Encoding.UTF8))
            {
                return reader.ReadToEnd();
            }
        }

        // ------------------------------------------------------------------
        // APLICAR EL FONDO (Win32 SystemParametersInfo vía P/Invoke)
        // ------------------------------------------------------------------

        private const uint SPI_SETDESKWALLPAPER = 0x0014;
        private const uint SPIF_UPDATEINIFILE = 0x01;
        private const uint SPIF_SENDCHANGE = 0x02;

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

        /// <summary>
        /// Aplica <paramref name="imagen"/> como fondo de pantalla usando
        /// SystemParametersInfo, que a diferencia de escribir el registro
        /// directamente, actualiza el escritorio al instante sin reiniciar
        /// explorer.exe y aplica a todos los monitores como una sola
        /// superficie. Registra el resultado; nunca lanza si falla, para no
        /// cortar la ejecución del programa por un solo intento fallido de
        /// SPI.
        /// </summary>
        private static void AplicarFondo(string imagen)
        {
            if (DryRun)
            {
                EscribirLog("DRY-RUN: se aplicaría '" + imagen + "' como fondo de pantalla.");
                return;
            }

            if (!File.Exists(imagen))
            {
                EscribirLog("AVISO: la imagen '" + imagen + "' no existe; no se aplicó ningún fondo.");
                return;
            }

            bool ok = SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, imagen, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
            if (!ok)
            {
                EscribirLog("AVISO: SystemParametersInfo devolvió error al aplicar '" + imagen + "'.");
            }
        }
    }
}

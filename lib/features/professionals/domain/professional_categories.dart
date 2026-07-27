/// Ordenação A-Z de nomes de categoria, ignorando acentos e caixa — o
/// `compareTo` puro do Dart joga acentuados depois do Z e o `order('name')`
/// do Postgres depende da collation do banco.
int compareCategoryNames(String a, String b) =>
    _categorySortKey(a).compareTo(_categorySortKey(b));

String _categorySortKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâãä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[íìîï]'), 'i')
    .replaceAll(RegExp(r'[óòôõö]'), 'o')
    .replaceAll(RegExp(r'[úùûü]'), 'u')
    .replaceAll('ç', 'c')
    .trim();

const List<String> professionalCategories = [
  'Ajudante',
  'Alpinista industrial',
  'Arquiteto',
  'Azulejista',
  'Bombeiro civil',
  'Bombeiro hidráulico',
  'Calheiro',
  'Carpinteiro',
  'Chaveiro',
  'Consultor técnico',
  'Dedetizador',
  'Designer de interiores',
  'Eletricista',
  'Eletricista automotivo',
  'Encanador',
  'Engenheiro civil',
  'Engenheiro eletricista',
  'Estucador',
  'Gesseiro',
  'Instalador de alarmes',
  'Instalador de antenas',
  'Instalador de câmeras',
  'Instalador de energia solar',
  'Instalador de portão automático',
  'Jardineiro',
  'Ladrilheiro',
  'Lavador de estofados',
  'Marceneiro',
  'Marmorista',
  'Mecânico',
  'Mecânico industrial',
  'Montador de móveis',
  'Operador de máquinas',
  'Pedreiro',
  'Pintor',
  'Piscineiro',
  'Projetista',
  'Serralheiro',
  'Servente',
  'Soldador',
  'Supervisor técnico',
  'Técnico de automação',
  'Técnico de CFTV',
  'Técnico de computadores',
  'Técnico de controles de acesso',
  'Técnico de eletrodomésticos',
  'Técnico de elevadores',
  'Técnico de energia solar',
  'Técnico de esquadrias',
  'Técnico de impressoras',
  'Técnico de informática',
  'Técnico de máquinas de lavar',
  'Técnico de refrigeração',
  'Técnico de segurança eletrônica',
  'Técnico de telefonia',
  'Técnico em automação predial',
  'Técnico em climatização',
  'Técnico em elétrica',
  'Técnico em hidráulica',
  'Técnico em manutenção predial',
  'Técnico em redes',
  'Vidraceiro',
];

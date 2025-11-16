#!/usr/bin/env Rscript
#' Generate Bilingual (English + Chinese) Functional Categories
#'
#' Creates indexed functional categories in both English and Chinese
#' for multi-language vector classification.
#'
#' Output:
#'   - data/taxonomy/functional_categories_bilingual.parquet
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Generating Bilingual Functional Categories\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

OUTPUT_FILE <- "/home/olier/ellenberg/data/taxonomy/functional_categories_bilingual.parquet"

# ============================================================================
# Bilingual Category Generation
# ============================================================================

cat("Generating bilingual categories (English + Chinese)...\n\n")

# Create comprehensive category list with matching indices
# Format: index, category_en, category_zh, kingdom, functional_group
bilingual_categories <- tribble(
  ~index, ~category_en, ~category_zh, ~kingdom, ~functional_group,

  # ==========================================================================
  # INSECTS - POLLINATORS
  # ==========================================================================
  "001", "bees", "蜜蜂", "Animalia", "pollinator",
  "002", "butterflies", "蝴蝶", "Animalia", "pollinator",
  "003", "moths", "蛾", "Animalia", "pollinator",
  "004", "hoverflies", "食蚜蝇", "Animalia", "pollinator",
  "005", "flies", "苍蝇", "Animalia", "pollinator",

  # ==========================================================================
  # INSECTS - HERBIVORES
  # ==========================================================================
  "006", "aphids", "蚜虫", "Animalia", "herbivore",
  "007", "caterpillars", "毛毛虫", "Animalia", "herbivore",
  "008", "beetles", "甲虫", "Animalia", "herbivore",
  "009", "weevils", "象甲", "Animalia", "herbivore",
  "010", "leafhoppers", "叶蝉", "Animalia", "herbivore",
  "011", "scale insects", "介壳虫", "Animalia", "herbivore",
  "012", "thrips", "蓟马", "Animalia", "herbivore",
  "013", "sawflies", "叶蜂", "Animalia", "herbivore",
  "014", "grasshoppers", "蚱蜢", "Animalia", "herbivore",
  "015", "locusts", "蝗虫", "Animalia", "herbivore",
  "016", "katydids", "蝈蝈", "Animalia", "herbivore",
  "017", "crickets", "蟋蟀", "Animalia", "herbivore",

  # ==========================================================================
  # INSECTS - PREDATORS
  # ==========================================================================
  "018", "ladybugs", "瓢虫", "Animalia", "predator",
  "019", "lacewings", "草蛉", "Animalia", "predator",
  "020", "ground beetles", "步甲", "Animalia", "predator",
  "021", "assassin bugs", "猎蝽", "Animalia", "predator",
  "022", "dragonflies", "蜻蜓", "Animalia", "predator",
  "023", "damselflies", "豆娘", "Animalia", "predator",
  "024", "mantises", "螳螂", "Animalia", "predator",

  # ==========================================================================
  # INSECTS - DECOMPOSERS
  # ==========================================================================
  "025", "termites", "白蚁", "Animalia", "decomposer",
  "026", "dung beetles", "粪金龟", "Animalia", "decomposer",
  "027", "carrion beetles", "埋葬虫", "Animalia", "decomposer",

  # ==========================================================================
  # INSECTS - OTHER
  # ==========================================================================
  "028", "ants", "蚂蚁", "Animalia", "other_insect",
  "029", "wasps", "黄蜂", "Animalia", "other_insect",
  "030", "cicadas", "蝉", "Animalia", "other_insect",
  "031", "mayflies", "蜉蝣", "Animalia", "other_insect",
  "032", "caddisflies", "石蛾", "Animalia", "other_insect",
  "033", "stoneflies", "石蝇", "Animalia", "other_insect",
  "034", "earwigs", "蠼螋", "Animalia", "other_insect",
  "035", "cockroaches", "蟑螂", "Animalia", "other_insect",
  "036", "stick insects", "竹节虫", "Animalia", "other_insect",

  # ==========================================================================
  # BIRDS
  # ==========================================================================
  "037", "songbirds", "鸣禽", "Animalia", "bird",
  "038", "warblers", "莺", "Animalia", "bird",
  "039", "sparrows", "麻雀", "Animalia", "bird",
  "040", "finches", "雀", "Animalia", "bird",
  "041", "thrushes", "鸫", "Animalia", "bird",
  "042", "wrens", "鹪鹩", "Animalia", "bird",
  "043", "chickadees", "山雀", "Animalia", "bird",
  "044", "nuthatches", "䴓", "Animalia", "bird",
  "045", "vireos", "绿鹃", "Animalia", "bird",
  "046", "tanagers", "唐纳雀", "Animalia", "bird",

  "047", "raptors", "猛禽", "Animalia", "bird",
  "048", "hawks", "鹰", "Animalia", "bird",
  "049", "eagles", "雕", "Animalia", "bird",
  "050", "owls", "猫头鹰", "Animalia", "bird",
  "051", "falcons", "隼", "Animalia", "bird",

  "052", "waterfowl", "水禽", "Animalia", "bird",
  "053", "ducks", "鸭", "Animalia", "bird",
  "054", "geese", "鹅", "Animalia", "bird",
  "055", "swans", "天鹅", "Animalia", "bird",

  "056", "woodpeckers", "啄木鸟", "Animalia", "bird",
  "057", "hummingbirds", "蜂鸟", "Animalia", "bird",
  "058", "swifts", "雨燕", "Animalia", "bird",
  "059", "swallows", "燕子", "Animalia", "bird",
  "060", "corvids", "鸦科", "Animalia", "bird",
  "061", "crows", "乌鸦", "Animalia", "bird",
  "062", "ravens", "渡鸦", "Animalia", "bird",
  "063", "jays", "松鸦", "Animalia", "bird",

  # ==========================================================================
  # MAMMALS
  # ==========================================================================
  "064", "bats", "蝙蝠", "Animalia", "mammal",
  "065", "microbats", "小蝙蝠", "Animalia", "mammal",
  "066", "megabats", "大蝙蝠", "Animalia", "mammal",

  "067", "rodents", "啮齿动物", "Animalia", "mammal",
  "068", "mice", "鼠", "Animalia", "mammal",
  "069", "rats", "大鼠", "Animalia", "mammal",
  "070", "voles", "田鼠", "Animalia", "mammal",
  "071", "squirrels", "松鼠", "Animalia", "mammal",
  "072", "chipmunks", "花栗鼠", "Animalia", "mammal",
  "073", "gophers", "囊鼠", "Animalia", "mammal",

  "074", "rabbits", "兔", "Animalia", "mammal",
  "075", "hares", "野兔", "Animalia", "mammal",
  "076", "deer", "鹿", "Animalia", "mammal",
  "077", "foxes", "狐狸", "Animalia", "mammal",
  "078", "badgers", "獾", "Animalia", "mammal",
  "079", "weasels", "鼬", "Animalia", "mammal",
  "080", "minks", "貂", "Animalia", "mammal",
  "081", "shrews", "鼩鼱", "Animalia", "mammal",
  "082", "hedgehogs", "刺猬", "Animalia", "mammal",

  # ==========================================================================
  # REPTILES & AMPHIBIANS
  # ==========================================================================
  "083", "lizards", "蜥蜴", "Animalia", "reptile",
  "084", "geckos", "壁虎", "Animalia", "reptile",
  "085", "skinks", "石龙子", "Animalia", "reptile",
  "086", "iguanas", "鬣蜥", "Animalia", "reptile",
  "087", "anoles", "变色蜥", "Animalia", "reptile",

  "088", "snakes", "蛇", "Animalia", "reptile",
  "089", "vipers", "蝰蛇", "Animalia", "reptile",
  "090", "colubrids", "游蛇", "Animalia", "reptile",

  "091", "turtles", "龟", "Animalia", "reptile",
  "092", "tortoises", "陆龟", "Animalia", "reptile",

  "093", "frogs", "蛙", "Animalia", "amphibian",
  "094", "toads", "蟾蜍", "Animalia", "amphibian",
  "095", "treefrogs", "树蛙", "Animalia", "amphibian",
  "096", "newts", "蝾螈", "Animalia", "amphibian",
  "097", "salamanders", "火蜥蜴", "Animalia", "amphibian",

  # ==========================================================================
  # ARACHNIDS & MYRIAPODS
  # ==========================================================================
  "098", "spiders", "蜘蛛", "Animalia", "arachnid",
  "099", "orb weavers", "圆网蛛", "Animalia", "arachnid",
  "100", "jumping spiders", "跳蛛", "Animalia", "arachnid",
  "101", "wolf spiders", "狼蛛", "Animalia", "arachnid",
  "102", "tarantulas", "捕鸟蛛", "Animalia", "arachnid",
  "103", "crab spiders", "蟹蛛", "Animalia", "arachnid",

  "104", "ticks", "蜱", "Animalia", "arachnid",
  "105", "mites", "螨", "Animalia", "arachnid",
  "106", "scorpions", "蝎", "Animalia", "arachnid",
  "107", "harvestmen", "盲蛛", "Animalia", "arachnid",

  "108", "centipedes", "蜈蚣", "Animalia", "myriapod",
  "109", "millipedes", "马陆", "Animalia", "myriapod",

  # ==========================================================================
  # MOLLUSKS & ANNELIDS
  # ==========================================================================
  "110", "snails", "蜗牛", "Animalia", "mollusk",
  "111", "slugs", "蛞蝓", "Animalia", "mollusk",

  "112", "earthworms", "蚯蚓", "Animalia", "annelid",

  # ==========================================================================
  # PLANTS - TREES
  # ==========================================================================
  "113", "oaks", "橡树", "Plantae", "tree",
  "114", "maples", "枫树", "Plantae", "tree",
  "115", "birches", "桦树", "Plantae", "tree",
  "116", "willows", "柳树", "Plantae", "tree",
  "117", "poplars", "杨树", "Plantae", "tree",
  "118", "ashes", "白蜡树", "Plantae", "tree",
  "119", "elms", "榆树", "Plantae", "tree",
  "120", "beeches", "山毛榉", "Plantae", "tree",
  "121", "chestnuts", "栗树", "Plantae", "tree",
  "122", "walnuts", "胡桃", "Plantae", "tree",
  "123", "hickories", "山核桃", "Plantae", "tree",
  "124", "lindens", "椴树", "Plantae", "tree",
  "125", "sycamores", "悬铃木", "Plantae", "tree",
  "126", "planes", "法国梧桐", "Plantae", "tree",
  "127", "tulip trees", "鹅掌楸", "Plantae", "tree",
  "128", "magnolias", "木兰", "Plantae", "tree",

  "129", "pines", "松树", "Plantae", "tree",
  "130", "spruces", "云杉", "Plantae", "tree",
  "131", "firs", "冷杉", "Plantae", "tree",
  "132", "cedars", "雪松", "Plantae", "tree",
  "133", "junipers", "杜松", "Plantae", "tree",
  "134", "cypresses", "柏树", "Plantae", "tree",
  "135", "hemlocks", "铁杉", "Plantae", "tree",
  "136", "larches", "落叶松", "Plantae", "tree",
  "137", "yews", "紫杉", "Plantae", "tree",
  "138", "redwoods", "红杉", "Plantae", "tree",
  "139", "sequoias", "巨杉", "Plantae", "tree",

  # ==========================================================================
  # PLANTS - SHRUBS
  # ==========================================================================
  "140", "roses", "玫瑰", "Plantae", "shrub",
  "141", "hollies", "冬青", "Plantae", "shrub",
  "142", "viburnums", "荚蒾", "Plantae", "shrub",
  "143", "rhododendrons", "杜鹃花", "Plantae", "shrub",
  "144", "azaleas", "映山红", "Plantae", "shrub",
  "145", "heaths", "石楠", "Plantae", "shrub",
  "146", "heathers", "帚石楠", "Plantae", "shrub",
  "147", "blueberries", "蓝莓", "Plantae", "shrub",
  "148", "huckleberries", "越橘", "Plantae", "shrub",
  "149", "cranberries", "蔓越莓", "Plantae", "shrub",
  "150", "dogwoods", "山茱萸", "Plantae", "shrub",
  "151", "sumacs", "漆树", "Plantae", "shrub",
  "152", "elderberries", "接骨木", "Plantae", "shrub",
  "153", "boxwoods", "黄杨", "Plantae", "shrub",
  "154", "lilacs", "丁香", "Plantae", "shrub",
  "155", "hydrangeas", "绣球花", "Plantae", "shrub",
  "156", "spireas", "绣线菊", "Plantae", "shrub",
  "157", "barberries", "小檗", "Plantae", "shrub",
  "158", "currants", "醋栗", "Plantae", "shrub",

  # ==========================================================================
  # PLANTS - HERBACEOUS
  # ==========================================================================
  "159", "grasses", "草", "Plantae", "herbaceous",
  "160", "sedges", "莎草", "Plantae", "herbaceous",
  "161", "rushes", "灯心草", "Plantae", "herbaceous",
  "162", "wildflowers", "野花", "Plantae", "herbaceous",
  "163", "asters", "紫菀", "Plantae", "herbaceous",
  "164", "goldenrods", "一枝黄花", "Plantae", "herbaceous",
  "165", "sunflowers", "向日葵", "Plantae", "herbaceous",
  "166", "coneflowers", "松果菊", "Plantae", "herbaceous",
  "167", "black-eyed susans", "黑心金光菊", "Plantae", "herbaceous",
  "168", "daisies", "雏菊", "Plantae", "herbaceous",
  "169", "lupines", "羽扇豆", "Plantae", "herbaceous",
  "170", "clovers", "三叶草", "Plantae", "herbaceous",
  "171", "vetches", "野豌豆", "Plantae", "herbaceous",
  "172", "milkweeds", "马利筋", "Plantae", "herbaceous",
  "173", "thistles", "蓟", "Plantae", "herbaceous",
  "174", "dandelions", "蒲公英", "Plantae", "herbaceous",
  "175", "plantains", "车前草", "Plantae", "herbaceous",
  "176", "buttercups", "毛茛", "Plantae", "herbaceous",
  "177", "violets", "堇菜", "Plantae", "herbaceous",
  "178", "geraniums", "天竺葵", "Plantae", "herbaceous",
  "179", "phlox", "福禄考", "Plantae", "herbaceous",
  "180", "primroses", "报春花", "Plantae", "herbaceous",
  "181", "irises", "鸢尾", "Plantae", "herbaceous",
  "182", "lilies", "百合", "Plantae", "herbaceous",

  # ==========================================================================
  # PLANTS - FERNS & VINES
  # ==========================================================================
  "183", "ferns", "蕨类", "Plantae", "fern",
  "184", "horsetails", "木贼", "Plantae", "fern",
  "185", "clubmosses", "石松", "Plantae", "fern",

  "186", "grapes", "葡萄", "Plantae", "vine",
  "187", "ivies", "常春藤", "Plantae", "vine",
  "188", "clematis", "铁线莲", "Plantae", "vine",
  "189", "hops", "啤酒花", "Plantae", "vine",
  "190", "morning glories", "牵牛花", "Plantae", "vine",
  "191", "bindweeds", "旋花", "Plantae", "vine",

  # ==========================================================================
  # PLANTS - FRUITS & VEGETABLES
  # ==========================================================================
  "192", "apples", "苹果", "Plantae", "fruit",
  "193", "pears", "梨", "Plantae", "fruit",
  "194", "cherries", "樱桃", "Plantae", "fruit",
  "195", "plums", "李子", "Plantae", "fruit",
  "196", "peaches", "桃", "Plantae", "fruit",
  "197", "apricots", "杏", "Plantae", "fruit",
  "198", "crabapples", "海棠果", "Plantae", "fruit",
  "199", "mulberries", "桑葚", "Plantae", "fruit",
  "200", "strawberries", "草莓", "Plantae", "fruit",
  "201", "blackberries", "黑莓", "Plantae", "fruit",
  "202", "raspberries", "覆盆子", "Plantae", "fruit",

  "203", "tomatoes", "番茄", "Plantae", "vegetable",
  "204", "peppers", "辣椒", "Plantae", "vegetable",
  "205", "eggplants", "茄子", "Plantae", "vegetable",
  "206", "squashes", "南瓜", "Plantae", "vegetable",
  "207", "pumpkins", "西葫芦", "Plantae", "vegetable",
  "208", "melons", "瓜", "Plantae", "vegetable",
  "209", "beans", "豆", "Plantae", "vegetable",
  "210", "peas", "豌豆", "Plantae", "vegetable",
  "211", "lettuce", "生菜", "Plantae", "vegetable",
  "212", "spinach", "菠菜", "Plantae", "vegetable",
  "213", "cabbage", "卷心菜", "Plantae", "vegetable",
  "214", "kale", "羽衣甘蓝", "Plantae", "vegetable",
  "215", "onions", "洋葱", "Plantae", "vegetable",
  "216", "garlic", "大蒜", "Plantae", "vegetable",

  # ==========================================================================
  # PLANTS - HERBS
  # ==========================================================================
  "217", "mints", "薄荷", "Plantae", "herb",
  "218", "sages", "鼠尾草", "Plantae", "herb",
  "219", "thymes", "百里香", "Plantae", "herb",
  "220", "oreganos", "牛至", "Plantae", "herb",
  "221", "basils", "罗勒", "Plantae", "herb",
  "222", "rosemarys", "迷迭香", "Plantae", "herb",
  "223", "lavenders", "薰衣草", "Plantae", "herb",

  # ==========================================================================
  # PLANTS - AQUATIC & OTHER
  # ==========================================================================
  "224", "water lilies", "睡莲", "Plantae", "aquatic",
  "225", "lotuses", "莲花", "Plantae", "aquatic",
  "226", "cattails", "香蒲", "Plantae", "aquatic",
  "227", "bulrushes", "藨草", "Plantae", "aquatic",
  "228", "pondweeds", "眼子菜", "Plantae", "aquatic",
  "229", "milfoils", "狐尾藻", "Plantae", "aquatic",
  "230", "duckweeds", "浮萍", "Plantae", "aquatic",
  "231", "hyacinths", "风信子", "Plantae", "aquatic",

  "232", "mosses", "苔藓", "Plantae", "bryophyte",
  "233", "sphagnum", "泥炭藓", "Plantae", "bryophyte",
  "234", "liverworts", "地钱", "Plantae", "bryophyte",

  "235", "lichens", "地衣", "Plantae", "lichen",
  "236", "algae", "藻类", "Plantae", "algae",
  "237", "seaweeds", "海藻", "Plantae", "algae",

  "238", "cacti", "仙人掌", "Plantae", "succulent",
  "239", "succulents", "多肉植物", "Plantae", "succulent",

  "240", "palms", "棕榈", "Plantae", "palm",
  "241", "bamboos", "竹子", "Plantae", "grass"
)

# ============================================================================
# Validation
# ============================================================================

cat("Validating bilingual categories...\n")

# Check for duplicate indices
dup_indices <- bilingual_categories %>%
  count(index) %>%
  filter(n > 1)

if (nrow(dup_indices) > 0) {
  cat("WARNING: Duplicate indices found:\n")
  print(as.data.frame(dup_indices))
  stop("Please remove duplicate indices before proceeding.")
}

# Check for duplicate English categories
dup_en <- bilingual_categories %>%
  count(category_en) %>%
  filter(n > 1)

if (nrow(dup_en) > 0) {
  cat("WARNING: Duplicate English categories found:\n")
  print(as.data.frame(dup_en))
  stop("Please remove duplicate English categories before proceeding.")
}

# Check for duplicate Chinese categories
dup_zh <- bilingual_categories %>%
  count(category_zh) %>%
  filter(n > 1)

if (nrow(dup_zh) > 0) {
  cat("WARNING: Duplicate Chinese categories found:\n")
  print(as.data.frame(dup_zh))
  stop("Please remove duplicate Chinese categories before proceeding.")
}

cat("  ✓ No duplicate indices or categories\n\n")

# ============================================================================
# Summary Statistics
# ============================================================================

cat("Category breakdown:\n")

summary_stats <- bilingual_categories %>%
  group_by(kingdom, functional_group) %>%
  summarise(count = n(), .groups = "drop") %>%
  arrange(kingdom, desc(count))

print(as.data.frame(summary_stats))

cat("\n")
cat(sprintf("Total categories: %d\n", nrow(bilingual_categories)))
cat(sprintf("  Animalia: %d\n", sum(bilingual_categories$kingdom == "Animalia")))
cat(sprintf("  Plantae: %d\n", sum(bilingual_categories$kingdom == "Plantae")))

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(bilingual_categories, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d bilingual functional categories\n",
            nrow(bilingual_categories)))

# ============================================================================
# Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n", sep = "")
cat(sprintf("Total categories: %d\n", nrow(bilingual_categories)))
cat(sprintf("Animalia: %d\n", sum(bilingual_categories$kingdom == "Animalia")))
cat(sprintf("Plantae: %d\n", sum(bilingual_categories$kingdom == "Plantae")))
cat("\nLanguages: English (en), Chinese (zh)\n")
cat("\nOutput file: ", OUTPUT_FILE, "\n", sep = "")
cat(rep("=", 80), "\n\n", sep = "")

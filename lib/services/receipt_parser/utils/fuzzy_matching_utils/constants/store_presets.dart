/// Static preset collections for common stores and restaurants.
class StorePresets {
  const StorePresets._();

  /// Fast food restaurant presets with spelling variations.
  static const Map<String, List<String>> fastFood = {
    'mcdonalds': ["mcdonald's", 'mcdonalds', 'mcd', 'mickey d', 'mickey ds'],
    'burger_king': ['burger king', 'bk', 'burgerking'],
    'wendys': ["wendy's", 'wendys', 'wendy'],
    'taco_bell': ['taco bell', 'tacobell', 'tbell'],
    'chipotle': ['chipotle', 'chipotle mexican grill', 'chipolte'],
    'subway': ['subway', 'sub way'],
    'chick_fil_a': ['chick-fil-a', 'chick fil a', 'chickfila', 'cfa'],
    'popeyes': ['popeyes', "popeye's", 'popeye'],
    'five_guys': ['five guys', 'fiveguys', '5 guys'],
    'in_n_out': ['in-n-out', 'in n out', 'innout'],
    'jack_in_the_box': ['jack in the box', 'jack box', 'jitb'],
    'sonic': ['sonic', 'sonic drive-in', 'sonic drive in'],
    'arbys': ["arby's", 'arbys', 'arby'],
    'kfc': ['kfc', 'kentucky fried chicken', 'kentucky fried'],
    'panda_express': ['panda express', 'pandaexpress', 'panda'],
    'del_taco': ['del taco', 'deltaco'],
    'whataburger': ['whataburger', 'what a burger'],
    'culvers': ["culver's", 'culvers', 'culver'],
    'zaxbys': ["zaxby's", 'zaxbys', 'zaxby'],
    'raising_canes': ["raising cane's", 'raising canes', 'canes'],
  };

  /// Casual dining restaurant presets with spelling variations.
  static const Map<String, List<String>> casualDining = {
    'applebees': ["applebee's", 'applebees', 'applebee'],
    'chilis': ["chili's", 'chilis', 'chili'],
    'olive_garden': ['olive garden', 'olivegarden'],
    'red_lobster': ['red lobster', 'redlobster'],
    'outback_steakhouse': ['outback steakhouse', 'outback'],
    'texas_roadhouse': ['texas roadhouse', 'texasroadhouse'],
    'buffalo_wild_wings': ['buffalo wild wings', 'bww', 'bdubs', 'b-dubs'],
    'tgi_fridays': ['tgi fridays', "tgi friday's", 'fridays', 'tgif'],
    'dennys': ["denny's", 'dennys', 'denny'],
    'ihop': ['ihop', 'i hop', 'international house of pancakes'],
    'cracker_barrel': ['cracker barrel', 'crackerbarrel'],
    'red_robin': ['red robin', 'redrobin'],
    'golden_corral': ['golden corral', 'goldencorral'],
    'cheesecake_factory': ['cheesecake factory', 'the cheesecake factory'],
    'pf_changs': ["p.f. chang's", 'pf changs', 'pf chang'],
    'longhorn_steakhouse': ['longhorn steakhouse', 'longhorn'],
    'hooters': ['hooters'],
    'bob_evans': ['bob evans', 'bobevans'],
    'waffle_house': ['waffle house', 'wafflehouse'],
    'perkins': ['perkins', 'perkins restaurant'],
  };

  /// Coffee shop presets with spelling variations.
  static const Map<String, List<String>> coffeeShops = {
    'starbucks': ['starbucks', 'starbuck', 'sbux'],
    'dunkin': ['dunkin', "dunkin'", 'dunkin donuts', 'dunkindonuts'],
    'peets_coffee': ["peet's coffee", 'peets coffee', 'peets', "peet's"],
    'tim_hortons': ['tim hortons', 'timhortons', "tim horton's", 'tims'],
    'caribou_coffee': ['caribou coffee', 'caribou'],
    'dutch_bros': ['dutch bros', 'dutchbros', 'dutch brothers'],
    'coffee_bean': ['coffee bean', 'the coffee bean', 'coffee bean and tea leaf'],
    'biggby': ['biggby', 'biggby coffee'],
    'scooters_coffee': ["scooter's coffee", 'scooters coffee', 'scooters'],
    'black_rock_coffee': ['black rock coffee', 'blackrock'],
    'gregorys_coffee': ["gregory's coffee", 'gregorys coffee'],
    'blue_bottle': ['blue bottle', 'blue bottle coffee', 'bluebottle'],
    'intelligentsia': ['intelligentsia', 'intelligentsia coffee'],
    'la_colombe': ['la colombe', 'lacolombe'],
    'philz_coffee': ['philz coffee', 'philz', "philz'"],
  };

  /// Grocery store presets with spelling variations.
  static const Map<String, List<String>> grocery = {
    'walmart': ['walmart', 'wal-mart', 'wal mart', 'walmartk'],
    'target': ['target', 'tgt'],
    'costco': ['costco', 'costco wholesale'],
    'trader_joes': ['trader joe', "trader joe's", 'trader joes', 'tjs'],
    'whole_foods': ['whole foods', 'wholefoods', 'wfm', 'whole foods market'],
    'kroger': ['kroger', "kroger's"],
    'safeway': ['safeway'],
    'publix': ['publix'],
    'aldi': ['aldi'],
    'lidl': ['lidl'],
    'heb': ['h-e-b', 'heb', 'h e b'],
    'meijer': ['meijer', "meijer's"],
    'winco': ['winco', 'winco foods'],
    'food_lion': ['food lion', 'foodlion'],
    'giant': ['giant', 'giant food'],
    'stop_and_shop': ['stop & shop', 'stop and shop', 'stopandshop'],
    'wegmans': ['wegmans', "wegman's"],
    'sprouts': ['sprouts', 'sprouts farmers market'],
    'fresh_market': ['fresh market', 'the fresh market'],
    'sams_club': ["sam's club", 'sams club', 'samsclub'],
    'bjs': ["bj's", 'bjs', 'bjs wholesale'],
    'market_basket': ['market basket', 'marketbasket'],
    'piggly_wiggly': ['piggly wiggly', 'pigglywiggly'],
    'harris_teeter': ['harris teeter', 'harristeeter'],
    'raleys': ["raley's", 'raleys'],
    'vons': ['vons'],
    'albertsons': ['albertsons', "albertson's"],
    'shaws': ["shaw's", 'shaws'],
    'acme': ['acme', 'acme markets'],
    'winn_dixie': ['winn-dixie', 'winn dixie', 'winndixie'],
  };

  /// Get all preset categories.
  static Map<String, Map<String, List<String>>> get allPresets => {
    'fast_food': fastFood,
    'casual_dining': casualDining,
    'coffee_shop': coffeeShops,
    'grocery': grocery,
  };

  /// Get all presets flattened into a single map.
  static Map<String, List<String>> get allPresetsFlat {
    final result = <String, List<String>>{};
    result.addAll(fastFood);
    result.addAll(casualDining);
    result.addAll(coffeeShops);
    result.addAll(grocery);
    return result;
  }
}

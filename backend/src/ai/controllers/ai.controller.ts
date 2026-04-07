import { Request, Response, NextFunction } from 'express';

interface AIResponse {
  response: string;
  suggestions: string[];
}

const responses: Record<string, AIResponse> = {
  food: {
    response: "Looking for food in London? Here are my top picks:\n\n🍕 **Franco Manca** - Best sourdough pizza in Brixton\n🍜 **Dishoom** - Incredible Bombay-style brunch in King's Cross\n🍔 **Honest Burger** - Quality burgers across London\n🥘 **Padella** - Fresh pasta in Borough Market (worth the queue!)\n\nWhat area are you in? I can give more specific recommendations!",
    suggestions: ["Best brunch spots", "Cheap eats near me", "Late night food"]
  },
  restaurant: {
    response: "Looking for food in London? Here are my top picks:\n\n🍕 **Franco Manca** - Best sourdough pizza in Brixton\n🍜 **Dishoom** - Incredible Bombay-style brunch in King's Cross\n🍔 **Honest Burger** - Quality burgers across London\n🥘 **Padella** - Fresh pasta in Borough Market (worth the queue!)\n\nWhat area are you in? I can give more specific recommendations!",
    suggestions: ["Best brunch spots", "Cheap eats near me", "Late night food"]
  },
  eat: {
    response: "Looking for food in London? Here are my top picks:\n\n🍕 **Franco Manca** - Best sourdough pizza in Brixton\n🍜 **Dishoom** - Incredible Bombay-style brunch in King's Cross\n🍔 **Honest Burger** - Quality burgers across London\n🥘 **Padella** - Fresh pasta in Borough Market (worth the queue!)\n\nWhat area are you in? I can give more specific recommendations!",
    suggestions: ["Best brunch spots", "Cheap eats near me", "Late night food"]
  },
  brunch: {
    response: "Brunch is huge in London! Here are the best spots:\n\n🥞 **The Wolseley** - Classic grand European cafe on Piccadilly\n🍳 **Caravan** - Great coffee and creative brunch in King's Cross\n🥑 **Farm Girl** - Healthy, Instagrammable in Notting Hill\n☕ **Dishoom** - Their bacon naan roll is legendary!\n\nBook ahead on weekends - these places fill up fast!",
    suggestions: ["Cafes with WiFi", "Bottomless brunch", "Quick breakfast"]
  },
  pub: {
    response: "Ah, a proper pint! Here are some London gems:\n\n🍺 **The Churchill Arms** - Kensington, covered in flowers\n🍻 **Ye Olde Cheshire Cheese** - Fleet St, since 1538\n🍺 **The Lamb and Flag** - Covent Garden classic\n🍻 **Gordon's Wine Bar** - Oldest wine bar in London\n\nShoreditch has the best cocktail scene if you want something fancier!",
    suggestions: ["Rooftop bars", "Student drink deals", "Cocktail bars"]
  },
  drink: {
    response: "Ah, a proper pint! Here are some London gems:\n\n🍺 **The Churchill Arms** - Kensington, covered in flowers\n🍻 **Ye Olde Cheshire Cheese** - Fleet St, since 1538\n🍺 **The Lamb and Flag** - Covent Garden classic\n🍻 **Gordon's Wine Bar** - Oldest wine bar in London\n\nShoreditch has the best cocktail scene if you want something fancier!",
    suggestions: ["Rooftop bars", "Student drink deals", "Cocktail bars"]
  },
  bar: {
    response: "London's bar scene is incredible! Here are my picks:\n\n🍸 **Nightjar** - Speakeasy vibes in Shoreditch\n🥃 **Swift** - Soho's coolest whisky bar\n🍹 **Dandelyan** (now Lyaness) - Award-winning cocktails\n🍾 **Sky Garden** - Free rooftop with amazing views\n\nFor student deals, check out Be At One during happy hour!",
    suggestions: ["Rooftop bars", "Speakeasy bars", "Happy hour deals"]
  },
  cocktail: {
    response: "London's bar scene is incredible! Here are my picks:\n\n🍸 **Nightjar** - Speakeasy vibes in Shoreditch\n🥃 **Swift** - Soho's coolest whisky bar\n🍹 **Dandelyan** (now Lyaness) - Award-winning cocktails\n🍾 **Sky Garden** - Free rooftop with amazing views\n\nFor student deals, check out Be At One during happy hour!",
    suggestions: ["Rooftop bars", "Speakeasy bars", "Happy hour deals"]
  },
  study: {
    response: "Need a study spot? London's got you covered:\n\n📚 **The British Library** - Free, massive, iconic\n☕ **Timberyard** - Great coffee + wifi in Soho\n📖 **Wellcome Collection** - Free library + cafe in Euston\n💻 **Google Campus** - Free coworking in Shoreditch\n\nMost uni libraries are open late during exam season too!",
    suggestions: ["Cafes with WiFi", "Free coworking spaces", "24hr study spots"]
  },
  library: {
    response: "Need a study spot? London's got you covered:\n\n📚 **The British Library** - Free, massive, iconic\n☕ **Timberyard** - Great coffee + wifi in Soho\n📖 **Wellcome Collection** - Free library + cafe in Euston\n💻 **Google Campus** - Free coworking in Shoreditch\n\nMost uni libraries are open late during exam season too!",
    suggestions: ["Cafes with WiFi", "Free coworking spaces", "24hr study spots"]
  },
  work: {
    response: "Looking for a place to work? Try these:\n\n💻 **Google Campus** - Free coworking in Shoreditch\n☕ **Second Home** - Beautiful creative workspace\n📱 **WeWork** - Various locations across London\n🏢 **British Library** - Free, quiet, great WiFi\n\nMany cafes also welcome remote workers during off-peak hours!",
    suggestions: ["Free coworking", "Cafes to work from", "Library spaces"]
  },
  tonight: {
    response: "Tonight in London? Here's what's happening:\n\n🎵 Check **DICE** app for gigs and club nights\n🎭 Last-minute theatre tickets on **TodayTix**\n🍽️ Walk-in restaurants along **Soho** and **Shoreditch**\n🎳 **All Star Lanes** for bowling + cocktails\n\nWhat vibe are you going for?",
    suggestions: ["Live music", "Club nights", "Chill evening"]
  },
  night: {
    response: "Tonight in London? Here's what's happening:\n\n🎵 Check **DICE** app for gigs and club nights\n🎭 Last-minute theatre tickets on **TodayTix**\n🍽️ Walk-in restaurants along **Soho** and **Shoreditch**\n🎳 **All Star Lanes** for bowling + cocktails\n\nWhat vibe are you going for?",
    suggestions: ["Live music", "Club nights", "Chill evening"]
  },
  club: {
    response: "Ready to party? Here's the London club scene:\n\n🎧 **Fabric** - Legendary techno in Farringdon\n💃 **XOYO** - Great lineup in Shoreditch\n🌙 **Printworks** - Massive warehouse events\n🎶 **Ministry of Sound** - The classic\n\nCheck DICE or RA (Resident Advisor) for tonight's events!",
    suggestions: ["Techno nights", "R&B clubs", "Student nights"]
  },
  music: {
    response: "London's music scene is unreal:\n\n🎸 **O2 Academy Brixton** - Best mid-size venue\n🎵 **Electric Brixton** - Great for indie/electronic\n🎤 **Jazz Cafe** - Camden's iconic venue\n🎹 **Ronnie Scott's** - World-class jazz in Soho\n\nDICE app has the best last-minute tickets!",
    suggestions: ["Jazz venues", "Rock gigs", "Free concerts"]
  },
  tube: {
    response: "For live Tube updates, check the Transport section in Discover! But generally:\n\n🚇 **Peak hours**: 7:30-9:30am and 5-7pm — avoid if possible\n💡 **Night Tube**: Fri & Sat on Central, Victoria, Jubilee, Northern, Piccadilly\n🚌 **Night buses** run 24/7 — the N routes follow tube lines\n💳 Use **contactless** — it's capped daily!",
    suggestions: ["Night tube times", "Bus alternatives", "Cheapest travel"]
  },
  transport: {
    response: "Getting around London:\n\n🚇 **Tube** - Fastest for central London\n🚌 **Bus** - Cheaper, better for short trips\n🚲 **Santander Bikes** - £1.65 per 30 mins\n🚶 **Walking** - Zone 1 is very walkable!\n\nAlways use contactless - it caps at £8.10/day!",
    suggestions: ["Tube tips", "Bus routes", "Bike hire"]
  },
  free: {
    response: "Free things to do in London:\n\n🏛️ **Museums** - British Museum, V&A, Natural History, Tate Modern\n🌳 **Parks** - Hyde Park, Regent's Park, Hampstead Heath\n🌅 **Sky Garden** - Free rooftop views (book ahead)\n🎭 **Southbank** - Street performers, free exhibitions\n\nLondon is one of the best cities for free entertainment!",
    suggestions: ["Free museums", "Free events today", "Park recommendations"]
  },
  museum: {
    response: "London's museums are world-class (and mostly free!):\n\n🏛️ **British Museum** - Ancient history\n🦕 **Natural History Museum** - Amazing architecture + dinosaurs\n🎨 **Tate Modern** - Contemporary art\n✈️ **Science Museum** - Interactive and fun\n🎭 **V&A** - Design and fashion\n\nAll free entry, some special exhibitions cost extra.",
    suggestions: ["Art galleries", "Kids activities", "Hidden gem museums"]
  },
  art: {
    response: "London's art scene is incredible:\n\n🎨 **Tate Modern** - Contemporary art (free)\n🖼️ **National Gallery** - Classic masterpieces (free)\n📸 **Saatchi Gallery** - Cutting-edge contemporary (free)\n🏛️ **Royal Academy** - Major exhibitions\n\nCheck out Shoreditch for amazing street art too!",
    suggestions: ["Street art tours", "Gallery openings", "Art classes"]
  },
  date: {
    response: "Planning a date in London? Try these:\n\n🌅 **Primrose Hill** - Sunset with city views\n🎬 **Electric Cinema** - Luxe seats, blankets, wine\n🍝 **Little Italy** - Cozy restaurants in Soho\n🚣 **Regent's Canal** - Walk from Camden to King's Cross\n🌙 **Skylight Rooftop** - Drinks with views in Tobacco Dock\n\nWhat's the vibe you're going for?",
    suggestions: ["Romantic restaurants", "Unique date ideas", "Budget-friendly dates"]
  },
  weather: {
    response: "London weather tips:\n\n☔ **Always carry an umbrella** - It can rain anytime\n🧥 **Layer up** - Temperature varies a lot\n☀️ **Summer** - Parks are amazing, grab a picnic\n❄️ **Winter** - Christmas markets are magical\n\nCheck BBC Weather or Met Office for accurate forecasts!",
    suggestions: ["Indoor activities", "Best parks", "Rainy day ideas"]
  },
  cheap: {
    response: "London on a budget:\n\n🍕 **Food markets** - Borough, Brick Lane, Camden\n🎫 **Rush tickets** - Theatre tickets same day\n🏛️ **Free museums** - British Museum, Tate, V&A\n🍺 **Wetherspoons** - Cheap pints everywhere\n🚌 **Bus > Tube** - Cheaper for short trips\n\nMonday-Friday happy hours are your friend!",
    suggestions: ["Student discounts", "Free events", "Budget eats"]
  },
  student: {
    response: "Student life in London:\n\n💸 **Discounts everywhere** - Always ask and show your card!\n🎫 **18+ Student Oyster** - 30% off travel\n🍺 **Student nights** - Monday/Tuesday at most clubs\n📚 **Senate House Library** - Access for all London uni students\n\nGet the Unidays and Student Beans apps for deals!",
    suggestions: ["Student bars", "Cheap eats", "Study spots"]
  },
  shopping: {
    response: "Shopping in London:\n\n🛍️ **Oxford Street** - High street everything\n💎 **Selfridges** - Iconic department store\n🎨 **Brick Lane** - Vintage and indie\n📦 **Westfield** - Massive malls (Stratford & Shepherd's Bush)\n🌸 **Covent Garden** - Boutiques and street performers\n\nFor vintage, try Portobello Market on Saturdays!",
    suggestions: ["Vintage shops", "Designer outlets", "Market days"]
  },
  market: {
    response: "London's best markets:\n\n🥐 **Borough Market** - Foodie heaven (Thu-Sat)\n🎨 **Portobello Road** - Vintage (Saturday best)\n🌮 **Brick Lane** - Food + vintage (Sunday)\n🌸 **Columbia Road** - Flowers (Sunday morning)\n🍜 **Camden Market** - Everything + food\n\nGo early to avoid the crowds!",
    suggestions: ["Food markets", "Vintage markets", "Night markets"]
  },
  help: {
    response: "I'm your LondonSnap AI assistant! I can help you with:\n\n🍕 **Food & Restaurants** - Where to eat\n🍺 **Pubs & Nightlife** - Best bars and clubs\n📚 **Study Spots** - Cafes and libraries\n🎭 **Events & Activities** - What's on\n🚇 **Transport** - Getting around\n💸 **Budget Tips** - Student deals\n\nJust ask me anything about London!",
    suggestions: ["Best restaurants", "What's on tonight", "Study cafes", "Transport tips"]
  }
};

const defaultResponse: AIResponse = {
  response: "Hey! I'm your LondonSnap AI — I know London inside out! 🏙️\n\nAsk me about:\n🍕 Food & restaurants\n🍺 Pubs & nightlife\n📚 Study spots & cafes\n🎭 Events & things to do\n🚇 Transport tips\n\nWhat are you looking for?",
  suggestions: ["Best restaurants", "What's on tonight", "Study cafes", "Pub recommendations"]
};

const findMatchingResponse = (message: string): AIResponse => {
  const lowerMessage = message.toLowerCase();
  
  // Check for keyword matches
  for (const [keyword, response] of Object.entries(responses)) {
    if (lowerMessage.includes(keyword)) {
      return response;
    }
  }
  
  return defaultResponse;
};

const getRandomDelay = (): number => {
  return Math.floor(Math.random() * 1000) + 500; // 500-1500ms
};

export const chatWithAI = async (
  req: Request,
  res: Response,
  _next: NextFunction
) => {
  try {
    const { message } = req.body;

    if (!message || typeof message !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Message is required',
      });
    }

    // Simulate AI thinking time
    const delay = getRandomDelay();
    await new Promise((resolve) => setTimeout(resolve, delay));

    const aiResponse = findMatchingResponse(message);

    res.json({
      success: true,
      data: {
        response: aiResponse.response,
        suggestions: aiResponse.suggestions,
      },
    });
  } catch (error) {
    _next(error);
  }
};

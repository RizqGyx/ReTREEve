import Foundation
import NaturalLanguage
import FoundationModels

struct Seed { let book: String; let text: String }
let seeds = [
 Seed(book:"Atomic Habits", text:"Small improvements repeated consistently can create meaningful change over time."),
 Seed(book:"Outliers", text:"Success can be influenced by effort, timing, opportunity, and environment."),
 Seed(book:"Deep Work", text:"Focused work without distraction can produce unusually valuable results."),
 Seed(book:"Mindset", text:"Abilities can develop through effort, strategy, and learning."),
 Seed(book:"The Psychology of Money", text:"Financial decisions can be shaped by personal experience as much as logic."),
]
let queries: [(String,String)] = [
 ("getting better little by little","Atomic Habits"),
 ("hard work isn't the only reason people succeed","Outliers"),
 ("something about avoiding distractions","Deep Work"),
 ("I remember reading something about being consistent","Atomic Habits"),
 ("people can get smarter if they keep trying","Mindset"),
 ("why people spend money differently","The Psychology of Money"),
 ("luck and being in the right place","Outliers"),
 ("concentrating for long stretches","Deep Work"),
 ("tiny changes add up","Atomic Habits"),
 ("feeling behind compared to others","Atomic Habits"),
]

@Generable
struct Expansion {
  @Guide(description: "12 to 18 short everyday phrases or single words a reader might use to search for this idea later, when they only vaguely remember it. Use plain, casual vocabulary that does NOT appear in the original sentence.")
  var phrases: [String]
}

let instructions = """
You help build a search index for a personal reading app.
Given one saved reading insight, list alternative everyday phrasings a person might type \
months later when they only half-remember it. Prefer common, casual words over the book's \
own vocabulary. No explanations, just the phrases.
"""

func expand(_ s: Seed) async -> [String] {
  let session = LanguageModelSession(instructions: instructions)
  do {
    let r = try await session.respond(
      to: "Book: \(s.book)\nInsight: \(s.text)",
      generating: Expansion.self)
    return r.content.phrases
  } catch { print("  FM error for \(s.book): \(error)"); return [] }
}

// generic english stoplist (NOT tuned to the test queries)
let stop: Set<String> = ["a","an","the","of","and","or","to","in","on","at","is","are","was","were","be","been","being","can","could","would","should","i","you","it","its","that","this","these","those","for","by","as","with","from","but","if","then","than","so","do","does","did","have","has","had","will","my","me","we","they","them","their","he","she","his","her","about","something","anything","some","any","more","most","much","very","just","also","up","down","out","over","when","what","how","why","which","who","there","here","not","no","only","other","others","get","got"]

func lemmas(_ s:String)->[String]{
  let t = NLTagger(tagSchemes:[.lemma]); t.string = s
  var out:[String]=[]
  t.enumerateTags(in: s.startIndex..<s.endIndex, unit:.word, scheme:.lemma, options:[.omitPunctuation,.omitWhitespace]){ tag,r in
    let l = (tag?.rawValue ?? String(s[r])).lowercased()
    if !stop.contains(l) && l.count>2 { out.append(l) }
    return true
  }
  return out
}

struct Index {
  var docs:[[String]]; var avgdl:Double
  init(_ d:[[String]]){ docs=d; avgdl=Double(d.reduce(0){$0+$1.count})/Double(d.count) }
  func score(_ q:[String],_ i:Int)->Double{
    let d=docs[i]; let dl=Double(d.count); var s=0.0
    for t in Set(q){
      let f=Double(d.filter{$0==t}.count); if f==0 {continue}
      let n=Double(docs.filter{$0.contains(t)}.count)
      let idf=log(1+(Double(docs.count)-n+0.5)/(n+0.5))
      s += idf*(f*2.2)/(f+1.2*(1-0.75+0.75*dl/avgdl))
    }
    return s
  }
}

func pad(_ s:String,_ n:Int)->String{ s.count>=n ? String(s.prefix(n-1))+" " : s+String(repeating:" ",count:n-s.count) }

let cacheURL = URL(fileURLWithPath: "docexp.json")
var expansions:[[String]] = []
if let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode([[String]].self, from: d), c.count == seeds.count {
  expansions = c; print("loaded cached doc expansions\n")
} else {
  print("Generating document expansions...\n")
  for s in seeds { expansions.append(await expand(s)) }
  try? JSONEncoder().encode(expansions).write(to: cacheURL)
}

// ---- QUERY-SIDE EXPANSION ----
@Generable
struct QExp {
  @Guide(description: "8 to 12 short alternative phrasings or related single words for this half-remembered search, using varied everyday vocabulary.")
  var terms: [String]
}
let qInstr = """
A reader is searching their own saved book highlights but only half-remembers the idea. Rewrite their vague query into alternative phrasings and related concept words that might appear in the highlight they are looking for. Plain everyday vocabulary. Phrases only.
"""
func expandQuery(_ q:String) async -> [String] {
  let s = LanguageModelSession(instructions: qInstr)
  do { return try await s.respond(to: q, generating: QExp.self).content.terms }
  catch { return [] }
}

let baseIdx = Index(seeds.map{ lemmas($0.book+" "+$0.text) })
let expIdx  = Index(seeds.enumerated().map{ lemmas($0.element.book+" "+$0.element.text+" "+expansions[$0.offset].joined(separator:" ")) })

let se = NLEmbedding.sentenceEmbedding(for: .english)!
let sVecs = seeds.map{ se.vector(for:$0.text) ?? [] }
func cos(_ a:[Double],_ b:[Double])->Double{
  var d=0.0,na=0.0,nb=0.0
  for i in 0..<min(a.count,b.count){ d+=a[i]*b[i]; na+=a[i]*a[i]; nb+=b[i]*b[i] }
  return (na==0||nb==0) ?0: d/(sqrt(na)*sqrt(nb))
}

// honest: returns nil rank when there is NO lexical signal at all
func rank(_ sc:[Double],_ exp:String, zeroIsNoSignal:Bool)->String{
  if zeroIsNoSignal && (sc.max() ?? 0) <= 0 { return "no signal" }
  let ord = sc.enumerated().sorted{ $0.element > $1.element }
  let r = (ord.firstIndex{ seeds[$0.offset].book==exp } ?? 98)+1
  return r==1 ? "1 HIT" : "#\(r) \(ord[0].offset == 98 ? "" : String(seeds[ord[0].offset].book.prefix(7)))"
}


func rankIdx(_ sc:[Double],_ exp:String)->Int?{
  if (sc.max() ?? 0) <= 0 { return nil }
  let ord = sc.enumerated().sorted{ $0.element > $1.element }.filter{ $0.element > 0 }
  guard let i = ord.firstIndex(where: { seeds[$0.offset].book==exp }) else { return nil }
  return i+1
}
print(String(repeating:"=",count:96))
print(pad("QUERY",44)+pad("rank(hybrid)",14)+pad("top1",8)+pad("in top3",10)+pad("#shown",8))
print(String(repeating:"-",count:96))
var t1=0, t3=0
for (q,exp) in queries {
  let qx = await expandQuery(q)
  let qlx = lemmas(q + " " + qx.joined(separator: " "))
  let lex = (0..<seeds.count).map{ expIdx.score(qlx,$0) }
  let qv = se.vector(for:q) ?? []
  let emb = sVecs.map{ cos(qv,$0) }
  // hybrid: lexical primary; embedding as small tiebreak so ordering is never arbitrary
  let maxL = lex.max() ?? 0
  let hybrid = (0..<seeds.count).map { i in (maxL > 0 ? lex[i]/maxL : 0) + 0.15*emb[i] }
  let shown = hybrid.enumerated().sorted{ $0.element > $1.element }.prefix(5).filter{ $0.element > 0.05 }
  let r = rankIdx(hybrid, exp)
  if r==1 {t1+=1}; if let r, r<=3 {t3+=1}
  print(pad(q,44)+pad(r.map{"#\($0)"} ?? "miss",14)+pad(r==1 ? "YES":"-",8)+pad((r ?? 9)<=3 ? "YES":"-",10)+pad("\(shown.count)",8))
}
print(String(repeating:"-",count:96))
print("HYBRID (doc-expansion + query-expansion + embedding tiebreak) over \(seeds.count) insights")
print("  top-1     \(t1)/\(queries.count)")
print("  recall@3  \(t3)/\(queries.count)   <-- the metric that matches 'Possible Matches'")

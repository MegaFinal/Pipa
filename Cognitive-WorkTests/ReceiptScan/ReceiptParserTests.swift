//
//  ReceiptParserTests.swift
//  Cognitive-WorkTests
//
//  Created by anshu Li on 04/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// The receipt reader on the OCR text of real receipts, as ``ReceiptTextReader`` produced it on
/// a device (personal data removed). Each one checks how many products were read and that their
/// sum is right, so a change to the parser's rules can't quietly break a receipt that worked.
struct ReceiptParserTests {

    /// Parses every page like ``ReceiptScanService`` does.
    private func read(_ pages: [String]) -> ReceiptScanResult {
        ReceiptScanResult(
            lines: pages.flatMap { ReceiptParser.parse($0).map(ReceiptScanLine.init) },
            printedTotals: pages.flatMap(ReceiptTotals.candidates(in:)),
            printedItemCount: pages.compactMap(ReceiptTotals.printedItemCount(in:)).last
        )
    }

    private func sum(_ result: ReceiptScanResult) -> Double {
        result.lines.map(\.total).reduce(0, +)
    }

    @Test func supermarketThreeItemsWithWeights() {
        let result = read([ReceiptFixtures.krill3])
        #expect(result.lines.count == 3)
        #expect(abs(sum(result) - 35.00) < 0.005)
        // 0,163 kg × 93,49 and 0,580 kg × 15,99, computed from the quantity lines.
        #expect(result.lines.map(\.weightKg) == [0, 0.163, 0.580])
        #expect(result.printedTotals.contains(35.00))
    }

    @Test func supermarketTwoItems() {
        let result = read([ReceiptFixtures.carrefour])
        #expect(result.lines.count == 2)
        #expect(abs(sum(result) - 13.38) < 0.005)
        #expect(result.printedTotals.contains(13.38))
    }

    @Test func restaurantBill() {
        let result = read([ReceiptFixtures.linx])
        #expect(result.lines.count == 15)
        #expect(abs(sum(result) - 1630.90) < 0.005)
        // "5 UN x R$ 99,00 = R$ 495,00"
        #expect(result.lines.contains { $0.quantity == 5 && abs($0.total - 495) < 0.005 })
        #expect(result.printedTotals.contains(1630.90))
    }

    @Test func supermarketMisreadUnits() {
        // "1 0V *", "1 UV x", "1 Ui x", "2 01 x": OCR misreads of "UN X".
        let result = read([ReceiptFixtures.krill13])
        #expect(result.lines.count == 13)
        #expect(abs(sum(result) - 175.24) < 0.005)
        #expect(result.printedItemCount == 13)
    }

    @Test func longSupermarketInTwoPhotos() {
        let result = read(ReceiptFixtures.sonda)
        #expect(result.lines.count == 51)
        #expect(abs(sum(result) - 786.44) < 0.005)
        #expect(result.printedItemCount == 52)
        // The one product cut between the two photos.
        #expect(result.missingItemNumbers == [35])
        // Barcodes are kept, to remember the product next time.
        #expect(result.lines.first { $0.itemNumber == 2 }?.barcode == "07898906925281")
        // 0,364 kg × 49,90: the total is computed, not the price per kg.
        #expect(result.lines.contains { $0.itemNumber == 25 && abs($0.total - 18.16) < 0.005 })
        // The footer's "S.DISP:452,51" never becomes a product's price.
        #expect(!result.lines.contains { abs($0.total - 452.51) < 0.005 })
    }
}

/// OCR text of real receipts (personal data removed).
enum ReceiptFixtures {
    static let krill3 = #"""
REDE KRILI SUPERMERCADOS LTDA
AV. ANCHIETA            2,300
JARDIM ALBATROZ - BERTIOGA - SP
CNPJ:21.010.503/0014-32 TE:738.091.278.116
DOCOMENTO ALXILIAR DA NUTA FIS AL
DE CONS CIDOR ELETRONICA
SQ.CODIGO               DESCRICAO                         QTD VL.UNIT ST TOTAL
0789::64027117 QJ.MUSS.AUR.FAT.150g 1 UN x 10,49 T01 10,49
2 02007300000000 PE.PE.SE.FT.EMD.kg 0,163 KG x 93,49 F                           15,24
)3 02002173000000 PAO FRANCES kg                 0,580 KG x 15,99 T04 9.27
QTD TOTAL DE ITENS                                                         003
VALOR TOTA. (R$)                                                       35,00
Cartao Debito                                                           35,00
"""#
    static let carrefour = #"""
CNPJ: 45.543.915/0699-71 CARREFOUR COMERCIO E INDUSTRIA LTDA
RUA NARIA ANTONIA, 257, CONSOLACAO
Sao Paulo - SF
Documento Auxiliar Nata Fiscal de Consumidor Eletronica
# CODIGO DESCRICAO QTDE UN VALOR UNIT (VL TR) VALOR TOTAL
001 8649642 SUCO REFR NATURAL ON               1 un x 7,89 (2,15) 7,89
002 4392949 SALG MILHO CHEETOS C 1 un x 5,49 (1,50) 5,49
Qtde totai de itens                                                      13,38
Valor total R$
FORMA PAGAMENTO                                              VALOR PAGO R$
Vale Alimentacao                                                         13,38
"""#
    static let linx = #"""
LINX
SEM VALOR FISCAL
AGUARDE CUPOM FISCAL
6:00
1ESA:                   39 CT:                    48
escricao Qtde                 Vlr. Unit.                              Subtotal
UCO MORANGO 300ML
1 UN x R$                     18,00 = R$                    18,00
UCO LIMAO 300ML
1 UN x R$                     12,90 = R$                   12,90
ODIZIO FRALDINHA
5 UN x R$                     99,00 = R$                 495,00
20 LIMAO
1 UN x R$                     18,00 = R$                   18,00
JCO LARANJA 300ML
3 UN      x R$                18,00 = R$                   54,00
JARANA ANTARCTICA ZERO 350ML
1 UN x R$                  15,00 = R$                      15,00
JARANA ANTARCTICA 350ML
1 UN x R$                    15,00 = R$                    15,00
(PERIENCIA COMPLETA SEMANA
1 UN x R$                  149,00 = R$                   149,00
DIZIO ALCATRA
1 UN x R$                     99,00 = R$                    99,00
PERIENCIA COMPLETA FIM DE SEMANA
1 UN x R$                   189,00 = R$              189,00
DIZIO FRANGO
3 UN x R$                     89,00 = R$             267,00
DIZIO FILE MIGNON
1 UN x R$                   119,00 = R$ 119,00
NEDO BORGES CEPAS CABERNET SAUVIGNON
1 UN x R$                120,00 = R$                   120,00
UA MINERAL PRATA C/GAS 300ML
2 UN x R$                   14,00 = Rą                       28,00
FE EXPRESSO
2 UN x R$                  16,00 = R$                        32,00
SEM VALOR FISCAL
ALOR TOTAL                                             R$             1.630,90
) TX. DE SERVIGO                                       R$                 244,64Ř
OTAL A PAGAR                                                     ,54
sumento em                                                        st
linx.com.Bi
"""#
    static let krill13 = #"""
REDE KRILL SUPERMERCADOS LTDA
AV'. ANCHIETA, 2.300
JARDIM ALBATROZ - BERTIOGA - SP
CNPJ: 21.010.503/0014-32 TE: 738.091.278.116
DOCUMETTO AUXILIAR DA NOTA FISCAL
DE CONSUMIDOR ELETRONICA
SJ.CODIGO                  DESCRICAO                        QTD VL.UNIT ST TOTP
01 07891000065440 LTE COND.NOC.TP 3959łę                      1 0V * 7,99 F              7.99
02 07091000055440 LTE COND.MOC.TP 395g                        1 UV x 7,99 F              7,99
03 02001038000000 BАNNА PRATA kg - 0,610 KG x 11,99 I                                    7,3
01 07091164027117 QJ.NUSS.AUR.FAT.150g                       1 UN x 10,49 T08          10.43
05 07091097107856 IOG.BAT.NAT.IN.1609                          1 Ui x 3,99 F              3.99
05 07091097107856 IOG.BAT.NAT.IN.160g                          1 01 x 3,99 F              3.99
0? 07091000379585 ACHOC.PO NESCAU 200g                         1 UN x 6,99 F              6.99
03 07898230715213 CERU.BA.WIT.GF.60001                        1 UN x 14,99 F             14.99
03 07091991295284 CE.BR.DU.MA.LT.260nl                        1 CX x 44.85 F            49.8
10 07893000394117 MA.CUALY C/SAL 250g                          1 Ul * 5,69 F              5,69
11 07091962051338 P.F.VISCONTI TR.400g                         2 01 x 5,99 F             11.98
12 07098654860254 CV.E.KR.EX.C.20un                           1 UN x 15,99 1             15,99
13 07091109714515 CHIN.TOP. BCO.43/44                         1 UN x 32,99 T08 32,99
QTD. TOTAL DE ITENS                                                            013
VALOR TOTAL (R$)                                                          175,24
Cartao Debito                                                            175,24
"""#
    static let sonda = [sondaPage1, sondaPage2]
    static let sondaPage1 = #"""
SONDA SUPERMERCADOS EXP.E TMP. CMPO                   01.937.633/0020-45
AV.GENERAL EDGAR FACO, 361. PIQVERI, SAO PAULO, SP
Documento Auxiliar da Nota Fiscal de Cunsumidor Eletronica
ITEM COD. DESC. QTO. UN. VL.UNIT ST VL.ITEN
001 09990814/9962/ SACULA BIOPL.REUT.CZA. 1OUN X 0.17 T18,00%
002 07898906925281 CACHACA MATUTA MEL LIMAO 1L                                  1.70
1UN X 62.90 T18.00₴șÍ                                                   052.90
003 07691150042117 AMACIANTE COMF.CONC.ENERGIA FLORAL 1L
1UN X 18.99 T18.00%                                                     18.99
004 07891156076178 SUPLEMENTO ALIM.YAKULT TAFFMAN 110ML
TUN X 4,98 T18,00%                                                       4,98
005 07898263456817 SUCO JAL LAR.1.3L
IUN X 16,79 T18,00%                                                    16,79
006 07896623100462 SUCO XANDO UVA 900ML 1UN X 14,79 T18,00₴
007 09002490247379 ENERGETICO RED BULL MELAN.LT.250ML                        14,79
TUN X 8,09 F1                                                            8,09
008 07894900083002 ALIMENTO AMEND.ADES 1L
1UN X 14,49 T18,00%                                                     14,49
009 07896623100882 SUCO XANDO GUIABA 900ML
TUN X 14,79 T18,00%                                                     14,79
010 07898230710201 CERVEJA BRDEN BADEN GOLDEN GF.600ML
1UN X 15,39 F1                                                         15,39
011 07898080640628 LEITE ITALAC SEMIDESN.C TPA.1L
2UN X 6,59 F1                                                           13,18
012 07896053470067 PAPEL TOALHA SORELLA ABSOL.F.D.110FL.2UN
1UN X 5,98 T18,00₺                                                      5,98
013 07891022640007 DETERGENTE LTQ.LIMP.COCO 500ML
TUN X 2,98 T18,00%                                                      2,98
014 07896200115346 FEIJAO BROTO LEGAL CAR.T.1 1KG
2UN X 9,98 I1                                                          19,96
015.07696901200150 ARRO2 BROTO LEGAL BCO.T.1 2KG
TUN X 11.19 I1                                                          11,19
016 07898416520723 MILHO PIP.KISAB.PREM.400G 1UN X 4,39 T18,00%
017 07622210907469 CHOCOLATE MILKA LU 87G                                     4,39
= 1UN X 17,90 F1                                                          17,90
018 07622201050757 CHOCOLATE MILKA CARAMEL 100G
1UN X 23,70 F1                                                          23,70
019 00000000048248 GRUSTOLI C PINGA KG
B 0,210KG X 44,90 T18,00₴                                                   9,43
02C 07896048200051 VINAGRE CASTELO ALC.750ML
1UN X 5,99 T18,00%                                                        5,99
021.07896292347786 SELEJA LEG.PREDILECTA CONS.LT.170G
2UN X 5,19 118,00%                                                      10,38
022 07896102500608 MILHO VDE.QUERO CORS.LT.170G
1UN X 4,69 118,00₴                                                       4,69
023 07896228100164 MASSA MAS.LEVE PASTEL CUMB.500G
TUN X 8,69 T12,00%                                                       8,69
024 07896036095041 EXTRATO TOM.ELEF.LT.130G
3UN X 4,89 F1                                                           14.67
00000000001441 QUEIJO MUSS.FAT.KG
0,364KG X 49,90 T18.00%                                                 18,16
00000000058681 FILE SALM.C PELE FKES.EMB.KG
R0,920KG X 109,90 T18,00%                                              101.11
027 00000000115018 COSTELA PERD.SUI.NA BRASA PED.EMB.KG
0,592KG X 27,99 T4,50%                                                   16,57
028 00000000917582 FRANGO RESFR.PC.KG
3,536KG Х 9,99 T4,50%                                                    35,32
00000000115056 AZEITONA VDE.RECH.KG
0,204KG X.56 , 90 T16,008                                               12,02
07891000253182 CREME LEITE NESTLE ZERO LACT.TP.200G
IUN / 4,09 FV                                                           4,69
07893000486953 MEIO ASA FGO.SAD.TULIPA CONG.1KG
1UN X 29.99 14,50€                                                     29.99
00000000145018 COSTELA PERO. SUI.NA BRASA PEO.EMB.KG
0,626KG Х 27.99 14.50%                                                 17,52
00000000123181 COPA LOMBO GRAN CORTE SUI:S D.FAT.EMB.KG
0.374KG X 31.99 T4,50₴                                                  11.96
034 00000000123181 COPA LOMBO GRAN CORTE SUI.S O.FAT.EMB.KG
35 07896051166856 0,434KG Х 31.99 T1.50%                                    13,88
CAMBE Z.LACT.O% MOR.510G

"""#
    static let sondaPage2 = #"""
036 07896051166474 REVUEIJNO T1AMBE NOLAC LI6.Z.LACT.4009 1UN X 20,69 F1
037 07896051164142 IDBORTE ITAMBE Z.LACT.DE MOR.AM.MAC.510G                   20.69
TUN X 7,49 F1                                                             7,49
038 07898906207989 MANTEIOR GA PESTRE                           E SAL 2006
1UN X 9,99 F1                                                            9.99
039 00000000004640 MEXERICA NJD #L
1,845KG X 5,49 I1                                                       10.13
040 00000000132718 BANANA NANICA FAVA NG
2,525KG X 7,79 T1                                                       19,67
041 07898943555151 TOMATE MALLMANN ECON.1KG
TUN X 6,59 I1                                                            6.59
042 07898943555403 TOMATE MALLMANN LIVRE ASR RED GRAPE 180S
2UN X 5,99 In                                                           11,98
043 07896518000020 AІND А:             -3 2000
TUN X 13,59 118,00%                                                     13.59
044 00000000003780 МАDA BALA KG
045   0,735KG Х 10,69 I1                                                      7,86
07891203010056 PAU PANCO FORMA 500G 1UN X 10,89 F1
046 07898331012761 MISTURA BULO FLFISCH.CHOCOMOUSSE SC.400G                   10,89
047 07891021002127 FILTRO PAP.BRIQLITA 103 30UN. 1UN X 7.99 T18,00%            7,99
1UN X 4,69 T18,00%                                                       4,59
048 07892840817749 AMENDOIN ELMA CHIPS JHP.400A
1UN X 16,99 T18,00%                                                     16,99
049 07896982100035 OVOS MANT1Q.BCD.T.EX.PVC 20UN 1UN X 14,99 I1
050 00000000025416 PAO FRANCES KG                                             14,99
0,594KG X 17,90 T12,00%                                                 10,63
051 08076808150072 MACARRAO BARILLA SEN.SPAG.7 500G 1UN X 14,39 T12,00%
052 00000000004015 PERA IMPORTADA KG                                          14.39
0,625KG X 16,99 I1Í                                                     10,62
QTD. TOTAL DE ITENS VALOR TOTAL                                                   52
CALOR A PAGAA                                                           R$ 793,93
T.E.F                                                                    R$ 793,93
R$ 793,9ęîę
"""#
}

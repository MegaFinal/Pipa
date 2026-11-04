//
//  TermsOfUse.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import Foundation

/// The app's Terms of Use: the legal text, split into sections so the screen can lay it out.
///
/// The text is legal content in Portuguese and is shown as written (it is not translated by the
/// string catalog). Bump ``version`` whenever it changes: users who accepted an older version
/// are asked to accept again (see clause 22).
struct TermsOfUse {

    /// One paragraph of a section.
    enum Paragraph: Hashable {
        /// Running text.
        case body(String)
        /// A lettered list entry ("a) …").
        case item(String)
        /// "Term: meaning", with the term in bold.
        case definition(term: String, text: String)
        /// A tappable contact line.
        case link(label: String, value: String, url: String)
    }

    /// One numbered section of the terms.
    struct Section: Identifiable {
        /// The section's number (`0` for the introduction).
        let id: Int
        /// `nil` for the introduction.
        let title: String?
        let paragraphs: [Paragraph]
    }

    /// The app's name shown in the terms.
    let appName: String
    /// Version of the terms. Accepting an older version asks the user to accept again.
    let version: String
    /// The date the terms were last changed, as shown to the user.
    let lastUpdated: String
    /// Every section, in order.
    let sections: [Section]

    /// The terms the app currently asks users to accept.
    static let current = TermsOfUse(
        appName: "Pipa",
        version: "1.1",
        lastUpdated: "9 de outubro de 2026",
        sections: allSections
    )

    /// The text of every section.
    private static let allSections: [Section] = [
        Section(
            id: 0,
            title: nil,
            paragraphs: [
                .body("Bem-vindo(a) ao Pipa."),
                .body("Estes Termos de Uso estabelecem as condições para acesso e utilização do aplicativo Pipa, disponibilizado por Jonas Fernando Nascimento de Melo."),
                .body("Ao criar uma conta, acessar ou utilizar o Aplicativo, o usuário declara que leu, compreendeu e concorda com estes Termos, bem como com a Política de Privacidade aplicável."),
                .body("Caso não concorde com qualquer disposição destes Termos, o usuário não deverá utilizar o Aplicativo.")
            ]
        ),
        Section(
            id: 1,
            title: "1. DEFINIÇÕES",
            paragraphs: [
                .body("Para fins destes Termos:"),
                .definition(term: "Aplicativo", text: "o software, suas funcionalidades, interfaces e serviços disponibilizados pela Plataforma."),
                .definition(term: "Usuário", text: "qualquer pessoa que acesse ou utilize o Aplicativo."),
                .definition(term: "Conteúdo", text: "qualquer texto, imagem, fotografia, comentário, descrição, publicação, arquivo ou outro material inserido, enviado ou disponibilizado pelo Usuário no Aplicativo."),
                .definition(term: "Conteúdo de Terceiros", text: "conteúdo publicado por Usuários ou por terceiros, que não tenha sido produzido diretamente pela Plataforma."),
                .definition(term: "Conta", text: "identificação individual criada pelo Usuário para utilização das funcionalidades que exigem autenticação."),
                .definition(term: "Plataforma", text: "Jonas Fernando Nascimento de Melo, responsável pela disponibilização e operação do Aplicativo.")
            ]
        ),
        Section(
            id: 2,
            title: "2. OBJETO E FUNCIONALIDADES",
            paragraphs: [
                .body("2.1. O Aplicativo oferece um ambiente digital no qual Usuários podem criar, publicar, visualizar e interagir com conteúdos disponibilizados por outros Usuários."),
                .body("2.2. Entre as funcionalidades disponibilizadas poderão estar:"),
                .item("a) criação e gerenciamento de perfil;"),
                .item("b) publicação de textos;"),
                .item("c) publicação de imagens;"),
                .item("d) visualização de conteúdos publicados por outros Usuários;"),
                .item("e) interação com conteúdos, quando essa funcionalidade estiver disponível;"),
                .item("f) pesquisa, organização ou categorização de conteúdos; e"),
                .item("g) outras funcionalidades que venham a ser disponibilizadas pela Plataforma."),
                .body("2.3. A Plataforma poderá alterar, suspender, limitar ou descontinuar funcionalidades do Aplicativo, observadas as obrigações legais aplicáveis e, quando necessário, mediante comunicação aos Usuários.")
            ]
        ),
        Section(
            id: 3,
            title: "3. ELEGIBILIDADE E CRIAÇÃO DA CONTA",
            paragraphs: [
                .body("3.1. O Usuário declara possuir capacidade legal para aceitar estes Termos."),
                .body("3.2. Caso a legislação aplicável exija autorização ou consentimento de responsável legal para utilização do Aplicativo, o Usuário deverá obtê-lo previamente."),
                .body("3.3. O Usuário é responsável pela veracidade das informações fornecidas à Plataforma e deverá mantê-las atualizadas."),
                .body("3.4. O Usuário é responsável pela segurança de suas credenciais de acesso."),
                .body("3.5. O Usuário não deverá compartilhar suas credenciais de acesso com terceiros quando isso puder comprometer a segurança da conta.")
            ]
        ),
        Section(
            id: 4,
            title: "4. CONTEÚDO GERADO PELOS USUÁRIOS",
            paragraphs: [
                .body("4.1. O Aplicativo permite que Usuários publiquem conteúdos próprios, incluindo textos e imagens, que poderão ser visualizados por outros Usuários conforme as funcionalidades e configurações de visibilidade disponíveis."),
                .body("4.2. O Usuário permanece responsável pelo conteúdo que publicar."),
                .body("4.3. Ao publicar determinado conteúdo, o Usuário declara que:"),
                .item("a) possui os direitos necessários para publicar o conteúdo;"),
                .item("b) possui autorização das pessoas eventualmente retratadas, quando necessária;"),
                .item("c) a publicação não viola direitos autorais, direitos de imagem, privacidade, honra, intimidade ou outros direitos de terceiros;"),
                .item("d) o conteúdo não viola a legislação aplicável;"),
                .item("e) o conteúdo não contém informações que o Usuário não esteja autorizado a divulgar; e"),
                .item("f) o conteúdo está de acordo com estes Termos e com as Diretrizes da Comunidade."),
                .body("4.4. A Plataforma atua como fornecedora do ambiente tecnológico que permite a publicação e visualização de conteúdos pelos Usuários."),
                .body("4.5. A Plataforma não assume responsabilidade pela veracidade, exatidão, legalidade, qualidade ou adequação dos conteúdos publicados pelos Usuários, ressalvadas as responsabilidades que não possam ser afastadas por lei."),
                .body("4.6. O fato de determinado conteúdo permanecer disponível no Aplicativo não significa que a Plataforma concorde, endosse ou valide seu conteúdo, suas opiniões ou suas informações."),
                .body("4.7. O Usuário reconhece que conteúdos publicados por terceiros podem ser incorretos, incompletos, ofensivos, inadequados ou eventualmente ilícitos.")
            ]
        ),
        Section(
            id: 5,
            title: "5. RESPONSABILIDADE DO USUÁRIO",
            paragraphs: [
                .body("5.1. O Usuário é integralmente responsável pelos conteúdos que inserir ou publicar no Aplicativo, dentro dos limites estabelecidos pela legislação aplicável."),
                .body("5.2. O Usuário não poderá utilizar o Aplicativo para:"),
                .item("a) publicar conteúdo ilegal ou que incentive a prática de crimes;"),
                .item("b) violar direitos autorais ou outros direitos de propriedade intelectual;"),
                .item("c) publicar imagens de terceiros sem autorização quando essa autorização for necessária;"),
                .item("d) divulgar dados pessoais de terceiros sem fundamento jurídico adequado;"),
                .item("e) praticar ou incentivar discriminação, perseguição, assédio ou ameaças;"),
                .item("f) divulgar conteúdo íntimo de terceiros sem autorização;"),
                .item("g) publicar material sexual envolvendo crianças ou adolescentes;"),
                .item("h) praticar fraude, estelionato, phishing ou outras práticas destinadas a enganar Usuários;"),
                .item("i) distribuir malware, vírus ou outros códigos maliciosos;"),
                .item("j) utilizar o Aplicativo para spam ou envio abusivo de conteúdo;"),
                .item("k) criar identidade falsa com o objetivo de causar dano ou obter vantagem ilícita;"),
                .item("l) utilizar o Aplicativo para perseguir, intimidar ou ameaçar terceiros;"),
                .item("m) publicar conteúdo que viole direitos de personalidade;"),
                .item("n) publicar conteúdo que infrinja qualquer legislação aplicável; ou"),
                .item("o) tentar comprometer, explorar ou contornar mecanismos de segurança do Aplicativo.")
            ]
        ),
        Section(
            id: 6,
            title: "6. DIREITOS AUTORAIS E PROPRIEDADE INTELECTUAL",
            paragraphs: [
                .body("6.1. O Usuário declara que possui os direitos necessários sobre os conteúdos que publicar ou que possui autorização suficiente para utilizá-los."),
                .body("6.2. A publicação de conteúdo de terceiros sem autorização poderá constituir violação de direitos autorais ou outros direitos legalmente protegidos."),
                .body("6.3. A legislação brasileira protege obras literárias, artísticas e científicas por meio da Lei nº 9.610/1998."),
                .body("6.4. O Usuário mantém a titularidade dos direitos sobre o conteúdo que produzir, salvo disposição específica em contrário."),
                .body("6.5. Ao publicar conteúdo no Aplicativo, o Usuário concede à Plataforma uma licença não exclusiva, gratuita, mundial e limitada ao funcionamento do Aplicativo, para hospedar, armazenar, reproduzir tecnicamente, processar, adaptar tecnicamente e disponibilizar o conteúdo aos demais Usuários de acordo com as funcionalidades escolhidas pelo próprio Usuário."),
                .body("6.6. A licença prevista nesta cláusula não transfere a propriedade intelectual do conteúdo para a Plataforma."),
                .body("6.7. A licença permanecerá válida enquanto necessária para a disponibilização do conteúdo e para cumprimento de obrigações legais, técnicas ou de segurança, podendo existir cópias de segurança ou registros que não sejam imediatamente eliminados por razões técnicas ou legais.")
            ]
        ),
        Section(
            id: 7,
            title: "7. DIREITO DE IMAGEM E PRIVACIDADE DE TERCEIROS",
            paragraphs: [
                .body("7.1. O Usuário deverá obter as autorizações necessárias antes de publicar imagens, vídeos ou outros conteúdos que permitam identificar terceiros, especialmente quando a utilização puder afetar sua privacidade, honra, reputação ou imagem."),
                .body("7.2. O Usuário não deverá utilizar o Aplicativo para expor informações pessoais, documentos, endereços, números de telefone, dados financeiros ou outras informações privadas de terceiros sem fundamento jurídico adequado."),
                .body("7.3. A publicação de conteúdo envolvendo nudez, intimidade ou vida privada de terceiros sem autorização poderá gerar consequências civis e criminais, além da remoção do conteúdo quando juridicamente cabível."),
                .body("7.4. A legislação brasileira estabelece proteção à intimidade, à vida privada, à honra e à imagem, além das regras específicas do Marco Civil da Internet.")
            ]
        ),
        Section(
            id: 8,
            title: "8. MODERAÇÃO E DENÚNCIAS",
            paragraphs: [
                .body("8.1. O Aplicativo é uma plataforma que permite a publicação de conteúdo pelos próprios Usuários."),
                .body("8.2. A Plataforma não garante a análise prévia ou a moderação integral de todo conteúdo publicado pelos Usuários."),
                .body("8.3. A ausência de moderação prévia não significa autorização para publicação de conteúdo ilícito ou contrário a estes Termos."),
                .body("8.4. A Plataforma poderá remover ou restringir conteúdos que representem risco à segurança do Aplicativo, aos Usuários ou a terceiros, ou que violem estes Termos, observada a legislação aplicável."),
                .body("8.5. A Plataforma não está obrigada a monitorar previamente todo conteúdo gerado por terceiros. Entretanto, eventuais obrigações legais de remoção, resposta a notificações ou atendimento a determinações judiciais deverão ser observadas."),
                .body("8.6. No Brasil, a responsabilidade de provedores por conteúdo gerado por terceiros é disciplinada pelo Marco Civil da Internet e por regulamentações aplicáveis, não podendo estes Termos afastar obrigações impostas por lei.")
            ]
        ),
        Section(
            id: 9,
            title: "9. CONTEÚDO ENVOLVENDO NUDES OU INTIMIDADE",
            paragraphs: [
                .body("9.1. É expressamente proibida a publicação de conteúdo íntimo de terceiros sem autorização."),
                .body("9.2. É expressamente proibida a publicação, solicitação, distribuição ou armazenamento de material de exploração sexual infantil."),
                .body("9.3. Conteúdos dessa natureza poderão ser removidos e, quando houver obrigação legal, poderão ser comunicados às autoridades competentes."),
                .body("9.4. O Marco Civil da Internet possui regra específica para situações envolvendo divulgação não autorizada de imagens, vídeos ou outros materiais contendo nudez ou atos sexuais de caráter privado.")
            ]
        ),
        Section(
            id: 10,
            title: "10. SEGURANÇA",
            paragraphs: [
                .body("10.1. A Plataforma adotará medidas técnicas e organizacionais razoáveis e compatíveis com a natureza do serviço para proteger os dados e sistemas sob sua responsabilidade contra acessos não autorizados, perda, destruição, alteração ou divulgação indevida."),
                .body("10.2. Nenhum sistema conectado à Internet pode ser considerado absolutamente seguro."),
                .body("10.3. O Usuário reconhece que riscos tecnológicos podem existir independentemente das medidas de segurança adotadas."),
                .body("10.4. O Usuário também é responsável por manter seu dispositivo, sistema operacional, aplicativo e credenciais protegidos.")
            ]
        ),
        Section(
            id: 11,
            title: "11. PRIVACIDADE E PROTEÇÃO DE DADOS",
            paragraphs: [
                .body("11.1. O tratamento de dados pessoais realizado pela Plataforma será regulado pela Política de Privacidade, que integra estes Termos para fins informativos."),
                .body("11.2. A Plataforma observará a legislação brasileira aplicável à proteção de dados pessoais, especialmente a Lei nº 13.709/2018 — Lei Geral de Proteção de Dados Pessoais (LGPD)."),
                .body("11.3. A LGPD estabelece princípios relacionados à privacidade, autodeterminação informativa, liberdade, proteção da intimidade, honra e imagem, entre outros."),
                .body("11.4. A Plataforma poderá tratar dados pessoais para finalidades como:"),
                .item("a) criação e gerenciamento de contas;"),
                .item("b) autenticação;"),
                .item("c) disponibilização das funcionalidades do Aplicativo;"),
                .item("d) segurança e prevenção de fraudes;"),
                .item("e) atendimento ao Usuário;"),
                .item("f) cumprimento de obrigações legais e regulatórias;"),
                .item("g) defesa de direitos em processos judiciais, administrativos ou arbitrais;"),
                .item("h) manutenção e melhoria do Aplicativo; e"),
                .item("i) outras finalidades descritas na Política de Privacidade."),
                .body("11.5. O tratamento de dados será realizado com fundamento jurídico adequado, conforme a finalidade e as circunstâncias de cada tratamento."),
                .body("11.6. O Usuário possui os direitos previstos na LGPD, incluindo, conforme aplicável, confirmação da existência de tratamento, acesso, correção, anonimização, bloqueio, eliminação, informação sobre compartilhamentos e demais direitos previstos em lei."),
                .body("11.7. A Plataforma poderá conservar determinadas informações após a exclusão da conta quando isso for necessário para cumprimento de obrigação legal, exercício regular de direitos, prevenção a fraudes, segurança ou outras hipóteses autorizadas pela legislação.")
            ]
        ),
        Section(
            id: 12,
            title: "12. DADOS PUBLICADOS PELO PRÓPRIO USUÁRIO",
            paragraphs: [
                .body("12.1. O Usuário reconhece que informações inseridas voluntariamente em conteúdos públicos poderão ser visualizadas por outros Usuários."),
                .body("12.2. O Usuário deverá evitar publicar informações pessoais desnecessárias, especialmente:"),
                .item("a) endereço residencial;"),
                .item("b) documentos de identificação;"),
                .item("c) informações bancárias;"),
                .item("d) senhas;"),
                .item("e) códigos de autenticação;"),
                .item("f) informações médicas ou altamente sensíveis de terceiros; e"),
                .item("g) qualquer outra informação cuja divulgação possa representar risco à sua segurança ou à segurança de terceiros."),
                .body("12.3. A Plataforma não será responsável por informações que o próprio Usuário deliberadamente tornar públicas, ressalvadas as responsabilidades legalmente atribuídas à Plataforma.")
            ]
        ),
        Section(
            id: 13,
            title: "13. COMPARTILHAMENTO DE DADOS",
            paragraphs: [
                .body("13.1. A Plataforma poderá utilizar prestadores de serviços e operadores necessários à operação do Aplicativo, como serviços de hospedagem, armazenamento, autenticação, análise de desempenho, segurança e infraestrutura tecnológica."),
                .body("13.2. O compartilhamento será realizado de acordo com as finalidades e bases legais aplicáveis e conforme descrito na Política de Privacidade."),
                .body("13.3. Dados poderão ser fornecidos a autoridades públicas quando houver obrigação legal, ordem judicial ou outra hipótese legalmente autorizada.")
            ]
        ),
        Section(
            id: 14,
            title: "14. RETENÇÃO E EXCLUSÃO DE DADOS",
            paragraphs: [
                .body("14.1. A Plataforma manterá dados pessoais pelo período necessário para cumprir as finalidades informadas e as obrigações legais aplicáveis."),
                .body("14.2. Após o término da finalidade, os dados poderão ser eliminados, anonimizados ou conservados nas hipóteses permitidas pela legislação."),
                .body("14.3. A LGPD prevê, como regra, a eliminação dos dados pessoais após o término do tratamento, ressalvadas hipóteses legais de conservação.")
            ]
        ),
        Section(
            id: 15,
            title: "15. SUSPENSÃO E ENCERRAMENTO DE CONTAS",
            paragraphs: [
                .body("15.1. A Plataforma poderá suspender, limitar ou encerrar uma conta quando houver:"),
                .item("a) violação destes Termos;"),
                .item("b) violação da legislação;"),
                .item("c) utilização fraudulenta do Aplicativo;"),
                .item("d) tentativa de comprometer a segurança do serviço;"),
                .item("e) publicação reiterada de conteúdo proibido;"),
                .item("f) solicitação do próprio Usuário; ou"),
                .item("g) outras situações justificadas pela segurança e funcionamento do Aplicativo."),
                .body("15.2. Quando juridicamente necessário, o Usuário poderá ser comunicado e ter oportunidade de apresentar esclarecimentos."),
                .body("15.3. O encerramento da conta não elimina automaticamente obrigações que, por sua natureza, devam permanecer vigentes.")
            ]
        ),
        Section(
            id: 16,
            title: "16. DISPONIBILIDADE DO APLICATIVO",
            paragraphs: [
                .body("16.1. A Plataforma buscará manter o Aplicativo disponível e funcional, mas não garante disponibilidade ininterrupta."),
                .body("16.2. O Aplicativo poderá ficar temporariamente indisponível em razão de:"),
                .item("a) manutenção;"),
                .item("b) atualizações;"),
                .item("c) falhas de infraestrutura;"),
                .item("d) problemas de conectividade;"),
                .item("e) ataques cibernéticos;"),
                .item("f) eventos de força maior; ou"),
                .item("g) outras circunstâncias fora do controle razoável da Plataforma."),
                .body("16.3. A Plataforma não garante que o Aplicativo estará livre de erros, vulnerabilidades ou interrupções.")
            ]
        ),
        Section(
            id: 17,
            title: "17. LIMITAÇÃO DE RESPONSABILIDADE",
            paragraphs: [
                .body("17.1. Na máxima extensão permitida pela legislação aplicável, a Plataforma não será responsável por:"),
                .item("a) conteúdos produzidos e publicados exclusivamente por Usuários;"),
                .item("b) informações falsas ou incorretas publicadas por terceiros;"),
                .item("c) interações entre Usuários;"),
                .item("d) danos decorrentes de relações estabelecidas entre Usuários fora do Aplicativo;"),
                .item("e) indisponibilidades decorrentes de fatores externos;"),
                .item("f) utilização inadequada do Aplicativo pelo Usuário; ou"),
                .item("g) divulgação voluntária de informações pelo próprio Usuário."),
                .body("17.2. As limitações desta seção não afastam responsabilidades que sejam impostas à Plataforma por normas de ordem pública ou pela legislação aplicável, incluindo aquelas relacionadas à proteção do consumidor, privacidade, segurança, direitos da personalidade e determinações judiciais.")
            ]
        ),
        Section(
            id: 18,
            title: "18. RELAÇÕES ENTRE USUÁRIOS",
            paragraphs: [
                .body("18.1. A Plataforma não é parte das relações, negociações, acordos ou interações eventualmente estabelecidas entre Usuários."),
                .body("18.2. O Usuário deverá utilizar cautela ao interagir com pessoas que conheça por meio do Aplicativo."),
                .body("18.3. A Plataforma não garante a identidade, reputação, intenções, capacidade, idoneidade ou veracidade das informações fornecidas por outros Usuários."),
                .body("18.4. O Usuário deverá evitar compartilhar informações pessoais ou realizar transações externas com pessoas desconhecidas sem avaliar adequadamente os riscos envolvidos.")
            ]
        ),
        Section(
            id: 19,
            title: "19. PUBLICIDADE E SERVIÇOS DE TERCEIROS",
            paragraphs: [
                .body("19.1. O Aplicativo poderá utilizar serviços, APIs, sistemas de hospedagem ou outras tecnologias fornecidas por terceiros."),
                .body("19.2. Serviços de terceiros poderão estar sujeitos a seus próprios termos e políticas."),
                .body("19.3. A Plataforma não controla integralmente serviços externos e não garante sua disponibilidade ou funcionamento.")
            ]
        ),
        Section(
            id: 20,
            title: "20. USO INTERNACIONAL",
            paragraphs: [
                .body("20.1. O Aplicativo poderá ser acessado por Usuários localizados em diferentes países."),
                .body("20.2. Quando aplicável, Usuários localizados nos Estados Unidos ou outros países poderão estar sujeitos a normas adicionais de proteção de dados, propriedade intelectual ou proteção do consumidor."),
                .body("20.3. Caso o Aplicativo seja disponibilizado a crianças menores de 13 anos nos Estados Unidos e realize tratamento de informações pessoais dessas crianças, poderá haver incidência da Children's Online Privacy Protection Act (COPPA) e de sua regulamentação."),
                .body("20.4. Caso a Plataforma disponibilize o serviço nos Estados Unidos e se enquadre nas condições previstas na legislação de direitos autorais daquele país, poderão ser aplicáveis mecanismos relacionados ao Digital Millennium Copyright Act (DMCA), incluindo procedimentos de notificação de alegadas violações de direitos autorais.")
            ]
        ),
        Section(
            id: 21,
            title: "21. PROPRIEDADE INTELECTUAL DA PLATAFORMA",
            paragraphs: [
                .body("21.1. O Aplicativo, sua interface, código, identidade visual, marca, logotipos, textos institucionais, elementos gráficos e demais componentes desenvolvidos pela Plataforma são protegidos pela legislação aplicável."),
                .body("21.2. Estes Termos não concedem ao Usuário qualquer direito de propriedade sobre esses elementos."),
                .body("21.3. É proibida a reprodução, modificação, distribuição ou exploração comercial não autorizada dos elementos pertencentes à Plataforma.")
            ]
        ),
        Section(
            id: 22,
            title: "22. ALTERAÇÕES DESTES TERMOS",
            paragraphs: [
                .body("22.1. A Plataforma poderá atualizar estes Termos para refletir alterações no Aplicativo, na legislação, em requisitos de segurança ou em suas práticas operacionais."),
                .body("22.2. Alterações relevantes serão comunicadas por meios razoáveis, quando necessário."),
                .body("22.3. A versão atualizada ficará disponível no Aplicativo ou em página indicada pela Plataforma."),
                .body("22.4. Quando a legislação exigir consentimento ou manifestação específica do Usuário, a Plataforma adotará o procedimento correspondente.")
            ]
        ),
        Section(
            id: 23,
            title: "23. LEGISLAÇÃO APLICÁVEL",
            paragraphs: [
                .body("23.1. Estes Termos serão interpretados de acordo com as leis brasileiras, sem prejuízo de normas obrigatórias eventualmente aplicáveis ao Usuário em razão de sua localização."),
                .body("23.2. Nada nestes Termos deverá ser interpretado como renúncia a direitos assegurados ao consumidor por normas de caráter obrigatório."),
                .body("23.3. Em relações de consumo, serão observadas as disposições aplicáveis do Código de Defesa do Consumidor."),
                .body("23.4. A Plataforma deverá disponibilizar informações claras sobre seus serviços e condições de utilização, em observância aos princípios de transparência e proteção do consumidor. O PROCON-SP, por exemplo, destaca a importância de informações claras sobre serviços e de medidas de segurança e confidencialidade em contratações eletrônicas.")
            ]
        ),
        Section(
            id: 24,
            title: "24. DISPOSIÇÕES FINAIS",
            paragraphs: [
                .body("24.1. Caso alguma disposição destes Termos seja considerada inválida ou inexequível, as demais disposições permanecerão em vigor na máxima extensão permitida pela legislação."),
                .body("24.2. A eventual tolerância da Plataforma quanto ao descumprimento de alguma disposição não constituirá renúncia ao direito de exigir seu cumprimento posteriormente."),
                .body("24.3. Estes Termos, juntamente com a Política de Privacidade e as Diretrizes da Comunidade, constituem o conjunto de regras aplicáveis à utilização do Aplicativo."),
                .body("24.4. O Usuário declara ter lido e compreendido estes Termos antes de utilizar o Aplicativo.")
            ]
        ),
        Section(
            id: 25,
            title: "25. CONTATO",
            paragraphs: [
                .body("Para dúvidas, solicitações, denúncias ou assuntos relacionados a estes Termos:"),
                .definition(term: "Responsável", text: "Jonas Fernando Nascimento de Melo"),
                .link(label: "E-mail", value: "jonasfnmelo@gmail.com", url: "mailto:jonasfnmelo@gmail.com"),
                .definition(term: "Versão", text: "1.1"),
                .definition(term: "Última atualização", text: "9 de outubro de 2026")
            ]
        )
    ]
}

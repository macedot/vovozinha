import Foundation

/// Lightweight in-app strings for PT / EN / ES (UI + generation helpers).
enum L10n {
    enum Key: String {
        // Tabs
        case tabLibrary, tabCreate, tabSettings

        // Onboarding
        case onboardingTitle, onboardingSubtitle, onboardingBullet1, onboardingBullet2
        case onboardingBullet3, onboardingBullet4, onboardingAgeToggle, onboardingStart
        case onboardingDevices

        // Library
        case libraryTitle, libraryEmptyTitle, libraryEmptyBody, libraryCreateCTA

        // Quick create
        case createTitle, createHeroQuestion, createHeroHint
        case createPhotoOptional, createChangePhoto, createRemove, createOnDeviceOnly
        case createDescription, createDescriptionPlaceholder
        case createNeedActor, createGenerate, createCustomize
        case createRandomHint, createImagePackHint

        // Custom create
        case customTitle, customHeader, customHeaderBody
        case customActor, customNamePlaceholder, customDescriptionPlaceholder
        case customAge, customWorld, customWorldOther, customLesson, customLessonOther
        case customIdea, customIdeaPlaceholder, customStyle
        case customPages, customPagesBody
        case customChoosePhoto, customSwapPhoto, customRemovePhoto
        case customActorReady, customNeedActor, customGenerate
        case customPhotoOnDevice

        // Generation
        case genCancel, genClose, genCreating, genReady, genFailed
        case genStepCharacter, genStepStory, genStepArt, genStepSave
        case genOpenBook, genBack, genRetry

        // Reader
        case readerTextOnlyBanner, readerArtPending, readerPageOf
        case readerListenPage, readerAudiobook, readerParentRead, readerExportPDF, readerDelete
        case readerReadAloudTitle, readerMissing, readerClose, readerOps
        case readerEmptyPages, readerExportFailed, readerNothingToSpeak

        // Settings
        case settingsTitle, settingsAbout, settingsApp, settingsVersion, settingsFocus, settingsDevices
        case settingsLanguage, settingsLanguageSystem, settingsLanguageHint
        case settingsOnDevice, settingsPackToggle, settingsPackHint
        case settingsImagePack, settingsImagePackDownload, settingsImagePackCancel
        case settingsImagePackDelete, settingsImagePackReady, settingsImagePackSizeHint
        case settingsImagePackDownloading, settingsImagePackFailed
        case settingsImagePackIntro
        case settingsImagePackBulletWifi, settingsImagePackBulletOffline, settingsImagePackBulletFallback
        case settingsImagePackPhaseListing, settingsImagePackPhaseDownloading
        case settingsImagePackPhaseExtracting, settingsImagePackPhaseVerifying
        case settingsImagePackLegacyHint
        case settingsVoice, settingsVoiceAuto, settingsVoiceHint, settingsVoicePremiumTip
        case settingsStorage, settingsStoriesSize, settingsRefreshSize
        case settingsPrivacy, settingsPrivacyBody
        case settingsParental, settingsResetAge
        case settingsFocusValue, settingsDevicesValue
        case settingsResources, settingsResourcesHint
        case settingsOSVersion

        // Shared
        case language

        // Feature banners
        case featureBannerGraphicsOff
        case featureBannerFoundationModelsOff
    }

    static func t(_ key: Key, _ lang: AppLanguage) -> String {
        table[key]?[lang] ?? table[key]?[.englishUS] ?? key.rawValue
    }

    private static let table: [Key: [AppLanguage: String]] = [
        .tabLibrary: [
            .portugueseBrazil: "Biblioteca",
            .englishUS: "Library",
            .spanishSpain: "Biblioteca"
        ],
        .tabCreate: [
            .portugueseBrazil: "Criar",
            .englishUS: "Create",
            .spanishSpain: "Crear"
        ],
        .tabSettings: [
            .portugueseBrazil: "Ajustes",
            .englishUS: "Settings",
            .spanishSpain: "Ajustes"
        ],

        .onboardingTitle: [
            .portugueseBrazil: "Vovozinha",
            .englishUS: "Vovozinha",
            .spanishSpain: "Vovozinha"
        ],
        .onboardingSubtitle: [
            .portugueseBrazil: "Histórias infantis da vovó,\nsó no seu iPhone.",
            .englishUS: "Bedtime stories from grandma,\nonly on your iPhone.",
            .spanishSpain: "Cuentos infantiles de la abuela,\nsolo en tu iPhone."
        ],
        .onboardingBullet1: [
            .portugueseBrazil: "Contos para crianças (3–8 anos), criados por adultos.",
            .englishUS: "Stories for children (ages 3–8), created by adults.",
            .spanishSpain: "Cuentos para niños (3–8 años), creados por adultos."
        ],
        .onboardingBullet2: [
            .portugueseBrazil: "Personagem a partir de foto de brinquedo ou descrição.",
            .englishUS: "Character from a toy photo or a short description.",
            .spanishSpain: "Personaje a partir de una foto de juguete o una descripción."
        ],
        .onboardingBullet3: [
            .portugueseBrazil: "Tudo offline: fotos e histórias não saem do aparelho.",
            .englishUS: "Fully offline: photos and stories never leave the device.",
            .spanishSpain: "Todo sin conexión: fotos e historias no salen del dispositivo."
        ],
        .onboardingBullet4: [
            .portugueseBrazil: "Sem contas, sem anúncios, sem rede social.",
            .englishUS: "No accounts, no ads, no social network.",
            .spanishSpain: "Sin cuentas, sin anuncios, sin red social."
        ],
        .onboardingAgeToggle: [
            .portugueseBrazil: "Tenho 18 anos ou mais e vou usar o app para criar histórias infantis.",
            .englishUS: "I am 18 or older and will use the app to create children's stories.",
            .spanishSpain: "Tengo 18 años o más y usaré la app para crear cuentos infantiles."
        ],
        .onboardingStart: [
            .portugueseBrazil: "Começar",
            .englishUS: "Get started",
            .spanishSpain: "Empezar"
        ],
        .onboardingDevices: [
            .portugueseBrazil: "iPhone 15+ · histórias com LLM no aparelho (Foundation Models: iOS 26+ e Apple Intelligence; pack local para A16 em breve)",
            .englishUS: "iPhone 15+ · on-device LLM stories (Foundation Models: iOS 26+ & Apple Intelligence; local pack for A16 coming soon)",
            .spanishSpain: "iPhone 15+ · historias con LLM en el dispositivo (Foundation Models: iOS 26+ y Apple Intelligence; pack local para A16 pronto)"
        ],

        .libraryTitle: [
            .portugueseBrazil: "Biblioteca",
            .englishUS: "Library",
            .spanishSpain: "Biblioteca"
        ],
        .libraryEmptyTitle: [
            .portugueseBrazil: "Nenhuma história ainda",
            .englishUS: "No stories yet",
            .spanishSpain: "Aún no hay historias"
        ],
        .libraryEmptyBody: [
            .portugueseBrazil: "Crie a primeira história infantil — basta descrever o personagem.",
            .englishUS: "Create the first children's story — just describe the character.",
            .spanishSpain: "Crea la primera historia infantil — solo describe el personaje."
        ],
        .libraryCreateCTA: [
            .portugueseBrazil: "Criar história",
            .englishUS: "Create story",
            .spanishSpain: "Crear historia"
        ],

        .createTitle: [
            .portugueseBrazil: "Criar",
            .englishUS: "Create",
            .spanishSpain: "Crear"
        ],
        .createHeroQuestion: [
            .portugueseBrazil: "Quem é o herói?",
            .englishUS: "Who is the hero?",
            .spanishSpain: "¿Quién es el héroe?"
        ],
        .createHeroHint: [
            .portugueseBrazil: "Descreva um brinquedo ou uma criança. O resto da história a Vovozinha inventa.",
            .englishUS: "Describe a toy or a child. Vovozinha invents the rest of the story.",
            .spanishSpain: "Describe un juguete o un niño. Vovozinha inventa el resto de la historia."
        ],
        .createPhotoOptional: [
            .portugueseBrazil: "Foto (opcional)",
            .englishUS: "Photo (optional)",
            .spanishSpain: "Foto (opcional)"
        ],
        .createChangePhoto: [
            .portugueseBrazil: "Trocar foto",
            .englishUS: "Change photo",
            .spanishSpain: "Cambiar foto"
        ],
        .createRemove: [
            .portugueseBrazil: "Remover",
            .englishUS: "Remove",
            .spanishSpain: "Quitar"
        ],
        .createOnDeviceOnly: [
            .portugueseBrazil: "Só no iPhone.",
            .englishUS: "Stays on iPhone only.",
            .spanishSpain: "Solo en el iPhone."
        ],
        .createDescription: [
            .portugueseBrazil: "Descrição",
            .englishUS: "Description",
            .spanishSpain: "Descripción"
        ],
        .createDescriptionPlaceholder: [
            .portugueseBrazil: "Ex.: ursinho azul de gravata · Nina de cabelo cacheado e pijama de estrelas",
            .englishUS: "E.g.: blue teddy with a bow tie · Nina with curly hair and star pajamas",
            .spanishSpain: "Ej.: osito azul con pajarita · Nina de pelo rizado y pijama de estrellas"
        ],
        .createNeedActor: [
            .portugueseBrazil: "Escreva quem é o personagem ou escolha uma foto.",
            .englishUS: "Describe the character or choose a photo.",
            .spanishSpain: "Describe el personaje o elige una foto."
        ],
        .createGenerate: [
            .portugueseBrazil: "Gerar história",
            .englishUS: "Generate story",
            .spanishSpain: "Generar historia"
        ],
        .createCustomize: [
            .portugueseBrazil: "Personalizar…",
            .englishUS: "Customize…",
            .spanishSpain: "Personalizar…"
        ],
        .createRandomHint: [
            .portugueseBrazil: "Mundo, lição, idade e estilo são escolhidos na hora. Use Personalizar se quiser escolher tudo.",
            .englishUS: "World, lesson, age, and style are chosen for you. Use Customize to pick everything.",
            .spanishSpain: "Mundo, lección, edad y estilo se eligen solos. Usa Personalizar para elegir todo."
        ],
        .createImagePackHint: [
            .portugueseBrazil: "Quer desenhos mais ricos nas páginas? Baixe o pacote de imagens em Ajustes (~1,5 GB, Wi‑Fi). Sem o pacote, as histórias usam desenhos simples. Depois do download, tudo fica no aparelho e offline.",
            .englishUS: "Want richer pictures on each page? Download the picture pack in Settings (~1.5 GB, Wi‑Fi). Without it, stories use simple drawings. After download, everything stays on this device and offline.",
            .spanishSpain: "¿Quieres dibujos más ricos en cada página? Descarga el paquete de imágenes en Ajustes (~1,5 GB, Wi‑Fi). Sin el paquete, las historias usan dibujos simples. Tras la descarga, todo queda en el dispositivo y offline."
        ],

        .customTitle: [
            .portugueseBrazil: "Personalizar",
            .englishUS: "Customize",
            .spanishSpain: "Personalizar"
        ],
        .customHeader: [
            .portugueseBrazil: "Controle total",
            .englishUS: "Full control",
            .spanishSpain: "Control total"
        ],
        .customHeaderBody: [
            .portugueseBrazil: "Escolha mundo, lição, idade e estilo. Ideal quando quiser algo bem específico.",
            .englishUS: "Choose world, lesson, age, and style. Ideal when you want something specific.",
            .spanishSpain: "Elige mundo, lección, edad y estilo. Ideal si quieres algo concreto."
        ],
        .customActor: [
            .portugueseBrazil: "Personagem (brinquedo ou criança)",
            .englishUS: "Character (toy or child)",
            .spanishSpain: "Personaje (juguete o niño)"
        ],
        .customNamePlaceholder: [
            .portugueseBrazil: "Nome — Ex.: Nina ou Ursinho Azul",
            .englishUS: "Name — e.g. Nina or Blue Teddy",
            .spanishSpain: "Nombre — ej.: Nina o Osito Azul"
        ],
        .customDescriptionPlaceholder: [
            .portugueseBrazil: "Descrição — Ex.: ursinho azul de gravata",
            .englishUS: "Description — e.g. blue teddy with a bow tie",
            .spanishSpain: "Descripción — ej.: osito azul con pajarita"
        ],
        .customAge: [
            .portugueseBrazil: "Faixa etária",
            .englishUS: "Age range",
            .spanishSpain: "Rango de edad"
        ],
        .customWorld: [
            .portugueseBrazil: "Mundo da história",
            .englishUS: "Story world",
            .spanishSpain: "Mundo de la historia"
        ],
        .customWorldOther: [
            .portugueseBrazil: "Ou escreva outro mundo…",
            .englishUS: "Or write another world…",
            .spanishSpain: "O escribe otro mundo…"
        ],
        .customLesson: [
            .portugueseBrazil: "Lição / valor",
            .englishUS: "Lesson / value",
            .spanishSpain: "Lección / valor"
        ],
        .customLessonOther: [
            .portugueseBrazil: "Ou outra lição…",
            .englishUS: "Or another lesson…",
            .spanishSpain: "O otra lección…"
        ],
        .customIdea: [
            .portugueseBrazil: "Ideia da história (opcional)",
            .englishUS: "Story idea (optional)",
            .spanishSpain: "Idea de la historia (opcional)"
        ],
        .customIdeaPlaceholder: [
            .portugueseBrazil: "Ex.: se perde na floresta e encontra um amigo que ensina a partilhar.",
            .englishUS: "E.g.: gets lost in the forest and meets a friend who teaches sharing.",
            .spanishSpain: "Ej.: se pierde en el bosque y encuentra un amigo que enseña a compartir."
        ],
        .customStyle: [
            .portugueseBrazil: "Estilo da ilustração",
            .englishUS: "Illustration style",
            .spanishSpain: "Estilo de ilustración"
        ],
        .customPages: [
            .portugueseBrazil: "Número de páginas",
            .englishUS: "Number of pages",
            .spanishSpain: "Número de páginas"
        ],
        .customPagesBody: [
            .portugueseBrazil: "Por enquanto todas as histórias têm 10 páginas com começo, meio e boa noite.",
            .englishUS: "For now every story has 10 pages with a beginning, middle, and good night.",
            .spanishSpain: "Por ahora cada historia tiene 10 páginas con principio, nudo y buenas noches."
        ],
        .customChoosePhoto: [
            .portugueseBrazil: "Escolher foto",
            .englishUS: "Choose photo",
            .spanishSpain: "Elegir foto"
        ],
        .customSwapPhoto: [
            .portugueseBrazil: "Trocar foto",
            .englishUS: "Change photo",
            .spanishSpain: "Cambiar foto"
        ],
        .customRemovePhoto: [
            .portugueseBrazil: "Remover foto",
            .englishUS: "Remove photo",
            .spanishSpain: "Quitar foto"
        ],
        .customActorReady: [
            .portugueseBrazil: "Personagem",
            .englishUS: "Character",
            .spanishSpain: "Personaje"
        ],
        .customNeedActor: [
            .portugueseBrazil: "Inclua o personagem: foto, nome ou descrição.",
            .englishUS: "Add a character: photo, name, or description.",
            .spanishSpain: "Incluye el personaje: foto, nombre o descripción."
        ],
        .customGenerate: [
            .portugueseBrazil: "Gerar história infantil",
            .englishUS: "Generate children's story",
            .spanishSpain: "Generar cuento infantil"
        ],
        .customPhotoOnDevice: [
            .portugueseBrazil: "Fica só no aparelho.",
            .englishUS: "Stays on this device only.",
            .spanishSpain: "Se queda solo en el dispositivo."
        ],

        .genCancel: [
            .portugueseBrazil: "Cancelar",
            .englishUS: "Cancel",
            .spanishSpain: "Cancelar"
        ],
        .genClose: [
            .portugueseBrazil: "Fechar",
            .englishUS: "Close",
            .spanishSpain: "Cerrar"
        ],
        .genCreating: [
            .portugueseBrazil: "Criando sua história…",
            .englishUS: "Creating your story…",
            .spanishSpain: "Creando tu historia…"
        ],
        .genReady: [
            .portugueseBrazil: "História pronta!",
            .englishUS: "Story ready!",
            .spanishSpain: "¡Historia lista!"
        ],
        .genFailed: [
            .portugueseBrazil: "Não deu certo",
            .englishUS: "Something went wrong",
            .spanishSpain: "Algo salió mal"
        ],
        .genStepCharacter: [
            .portugueseBrazil: "Entender o personagem",
            .englishUS: "Understand the character",
            .spanishSpain: "Entender el personaje"
        ],
        .genStepStory: [
            .portugueseBrazil: "Inventar o conto (texto)",
            .englishUS: "Write the story (text)",
            .spanishSpain: "Escribir el cuento (texto)"
        ],
        .genStepArt: [
            .portugueseBrazil: "Desenhar as cenas",
            .englishUS: "Draw the scenes",
            .spanishSpain: "Dibujar las escenas"
        ],
        .genStepSave: [
            .portugueseBrazil: "Guardar na biblioteca",
            .englishUS: "Save to library",
            .spanishSpain: "Guardar en la biblioteca"
        ],
        .genOpenBook: [
            .portugueseBrazil: "Abrir livro",
            .englishUS: "Open book",
            .spanishSpain: "Abrir libro"
        ],
        .genBack: [
            .portugueseBrazil: "Voltar",
            .englishUS: "Back",
            .spanishSpain: "Volver"
        ],
        .genRetry: [
            .portugueseBrazil: "Tentar de novo",
            .englishUS: "Try again",
            .spanishSpain: "Intentar de nuevo"
        ],

        .readerTextOnlyBanner: [
            .portugueseBrazil: "Livro em texto · sem imagem nesta página",
            .englishUS: "Text book · no image on this page",
            .spanishSpain: "Libro en texto · sin imagen en esta página"
        ],
        .readerArtPending: [
            .portugueseBrazil: "Cena ilustrada no aparelho (offline)",
            .englishUS: "On-device scene art (offline)",
            .spanishSpain: "Arte de escena en el dispositivo (offline)"
        ],
        .readerPageOf: [
            .portugueseBrazil: "Página %d de %d",
            .englishUS: "Page %d of %d",
            .spanishSpain: "Página %d de %d"
        ],
        .readerListenPage: [
            .portugueseBrazil: "Ouvir página",
            .englishUS: "Listen to page",
            .spanishSpain: "Escuchar página"
        ],
        .readerAudiobook: [
            .portugueseBrazil: "Audiolivro completo",
            .englishUS: "Full audiobook",
            .spanishSpain: "Audiolibro completo"
        ],
        .readerParentRead: [
            .portugueseBrazil: "Pai/mãe lê (texto)",
            .englishUS: "Parent reads (text)",
            .spanishSpain: "Padre/madre lee (texto)"
        ],
        .readerExportPDF: [
            .portugueseBrazil: "Exportar PDF",
            .englishUS: "Export PDF",
            .spanishSpain: "Exportar PDF"
        ],
        .readerDelete: [
            .portugueseBrazil: "Apagar história",
            .englishUS: "Delete story",
            .spanishSpain: "Borrar historia"
        ],
        .readerReadAloudTitle: [
            .portugueseBrazil: "Ler em voz alta",
            .englishUS: "Read aloud",
            .spanishSpain: "Leer en voz alta"
        ],
        .readerMissing: [
            .portugueseBrazil: "História não encontrada",
            .englishUS: "Story not found",
            .spanishSpain: "Historia no encontrada"
        ],
        .readerClose: [
            .portugueseBrazil: "Fechar",
            .englishUS: "Close",
            .spanishSpain: "Cerrar"
        ],
        .readerOps: [
            .portugueseBrazil: "Ops",
            .englishUS: "Oops",
            .spanishSpain: "Ups"
        ],
        .readerEmptyPages: [
            .portugueseBrazil: "Esta história não tem páginas.",
            .englishUS: "This story has no pages.",
            .spanishSpain: "Esta historia no tiene páginas."
        ],
        .readerExportFailed: [
            .portugueseBrazil: "Não foi possível exportar o PDF.",
            .englishUS: "Could not export the PDF.",
            .spanishSpain: "No se pudo exportar el PDF."
        ],
        .readerNothingToSpeak: [
            .portugueseBrazil: "Esta página não tem texto para ler em voz alta.",
            .englishUS: "This page has no text to read aloud.",
            .spanishSpain: "Esta página no tiene texto para leer en voz alta."
        ],

        .settingsTitle: [
            .portugueseBrazil: "Ajustes",
            .englishUS: "Settings",
            .spanishSpain: "Ajustes"
        ],
        .settingsAbout: [
            .portugueseBrazil: "Sobre",
            .englishUS: "About",
            .spanishSpain: "Acerca de"
        ],
        .settingsApp: [
            .portugueseBrazil: "App",
            .englishUS: "App",
            .spanishSpain: "App"
        ],
        .settingsVersion: [
            .portugueseBrazil: "Versão",
            .englishUS: "Version",
            .spanishSpain: "Versión"
        ],
        .settingsFocus: [
            .portugueseBrazil: "Foco",
            .englishUS: "Focus",
            .spanishSpain: "Enfoque"
        ],
        .settingsDevices: [
            .portugueseBrazil: "Dispositivos",
            .englishUS: "Devices",
            .spanishSpain: "Dispositivos"
        ],
        .settingsFocusValue: [
            .portugueseBrazil: "Histórias infantis offline",
            .englishUS: "Offline children's stories",
            .spanishSpain: "Cuentos infantiles sin conexión"
        ],
        .settingsDevicesValue: [
            .portugueseBrazil: "iPhone 15+ (gerar: FM iOS 26+ IA, ou pack A16 em breve)",
            .englishUS: "iPhone 15+ (generate: FM iOS 26+ AI, or A16 pack soon)",
            .spanishSpain: "iPhone 15+ (generar: FM iOS 26+ IA, o pack A16 pronto)"
        ],
        .settingsLanguage: [
            .portugueseBrazil: "Idioma",
            .englishUS: "Language",
            .spanishSpain: "Idioma"
        ],
        .settingsLanguageSystem: [
            .portugueseBrazil: "Sistema",
            .englishUS: "System",
            .spanishSpain: "Sistema"
        ],
        .settingsLanguageHint: [
            .portugueseBrazil: "Afeta a interface e o idioma das histórias geradas. O padrão segue o idioma do iPhone.",
            .englishUS: "Affects the interface and generated story language. Default follows the iPhone language.",
            .spanishSpain: "Afecta la interfaz y el idioma de las historias. Por defecto sigue el idioma del iPhone."
        ],
        .settingsOnDevice: [
            .portugueseBrazil: "Inteligência no aparelho",
            .englishUS: "On-device intelligence",
            .spanishSpain: "Inteligencia en el dispositivo"
        ],
        .settingsPackToggle: [
            .portugueseBrazil: "Pack neural de ilustração instalado",
            .englishUS: "Neural illustration pack installed",
            .spanishSpain: "Pack neural de ilustración instalado"
        ],
        .settingsPackHint: [
            .portugueseBrazil: "Opcional: um pacote de imagens deixa as páginas com cenas mais ricas. A internet só é usada no download; depois a arte roda no aparelho, offline.",
            .englishUS: "Optional: a picture pack makes story pages look richer. The internet is only used for the download; afterward, art runs on this device, offline.",
            .spanishSpain: "Opcional: un paquete de imágenes hace las páginas más ricas. Internet solo se usa al descargar; luego el arte corre en el dispositivo, offline."
        ],
        .settingsImagePack: [
            .portugueseBrazil: "Imagens da história (opcional)",
            .englishUS: "Story pictures (optional download)",
            .spanishSpain: "Imágenes de la historia (opcional)"
        ],
        .settingsImagePackIntro: [
            .portugueseBrazil: "Pacote de ilustrações no aparelho para cenas suaves em cada página do conto.",
            .englishUS: "On-device illustration pack for soft scenes on every story page.",
            .spanishSpain: "Paquete de ilustraciones en el dispositivo para escenas suaves en cada página."
        ],
        .settingsImagePackBulletWifi: [
            .portugueseBrazil: "Cerca de 1,5 GB · use Wi‑Fi (rede só nesta etapa).",
            .englishUS: "About 1.5 GB · use Wi‑Fi (network only for this step).",
            .spanishSpain: "Unos 1,5 GB · usa Wi‑Fi (red solo en este paso)."
        ],
        .settingsImagePackBulletOffline: [
            .portugueseBrazil: "Depois do download, as cenas ficam no telefone e funcionam offline.",
            .englishUS: "After download, scenes stay on this phone and work offline.",
            .spanishSpain: "Tras la descarga, las escenas se quedan en el teléfono y funcionan offline."
        ],
        .settingsImagePackBulletFallback: [
            .portugueseBrazil: "Sem o pacote, as histórias ainda funcionam com desenhos simples.",
            .englishUS: "Without the pack, stories still work with simple drawings.",
            .spanishSpain: "Sin el paquete, las historias siguen funcionando con dibujos simples."
        ],
        .settingsImagePackDownload: [
            .portugueseBrazil: "Baixar pacote de imagens",
            .englishUS: "Download picture pack",
            .spanishSpain: "Descargar paquete de imágenes"
        ],
        .settingsImagePackCancel: [
            .portugueseBrazil: "Cancelar download",
            .englishUS: "Cancel download",
            .spanishSpain: "Cancelar descarga"
        ],
        .settingsImagePackDelete: [
            .portugueseBrazil: "Remover pacote de imagens",
            .englishUS: "Remove picture pack",
            .spanishSpain: "Eliminar paquete de imágenes"
        ],
        .settingsImagePackReady: [
            .portugueseBrazil: "Pacote pronto · cenas no aparelho",
            .englishUS: "Picture pack ready · scenes on this device",
            .spanishSpain: "Paquete listo · escenas en el dispositivo"
        ],
        .settingsImagePackSizeHint: [
            .portugueseBrazil: "Download único recomendado. Use Wi‑Fi; cerca de 1,5 GB. Depois fica tudo no aparelho.",
            .englishUS: "One recommended download. Use Wi‑Fi; about 1.5 GB. Then everything stays on this device.",
            .spanishSpain: "Una descarga recomendada. Usa Wi‑Fi; unos 1,5 GB. Luego todo queda en el dispositivo."
        ],
        .settingsImagePackDownloading: [
            .portugueseBrazil: "Baixando pacote…",
            .englishUS: "Downloading pack…",
            .spanishSpain: "Descargando paquete…"
        ],
        .settingsImagePackPhaseListing: [
            .portugueseBrazil: "Preparando download…",
            .englishUS: "Preparing download…",
            .spanishSpain: "Preparando la descarga…"
        ],
        .settingsImagePackPhaseDownloading: [
            .portugueseBrazil: "Baixando…",
            .englishUS: "Downloading…",
            .spanishSpain: "Descargando…"
        ],
        .settingsImagePackPhaseExtracting: [
            .portugueseBrazil: "Descompactando no aparelho…",
            .englishUS: "Unpacking on this device…",
            .spanishSpain: "Descomprimiendo en el dispositivo…"
        ],
        .settingsImagePackPhaseVerifying: [
            .portugueseBrazil: "Verificando arquivos…",
            .englishUS: "Checking files…",
            .spanishSpain: "Comprobando archivos…"
        ],
        .settingsImagePackLegacyHint: [
            .portugueseBrazil: "Há um pacote antigo instalado. Remova e baixe de novo para as melhores imagens.",
            .englishUS: "An older picture pack is installed. Remove it and download again for the best story pictures.",
            .spanishSpain: "Hay un paquete antiguo instalado. Elimínalo y vuelve a descargar para las mejores imágenes."
        ],
        .settingsImagePackFailed: [
            .portugueseBrazil: "Não foi possível baixar",
            .englishUS: "Couldn’t download",
            .spanishSpain: "No se pudo descargar"
        ],
        .settingsVoice: [
            .portugueseBrazil: "Voz da narração",
            .englishUS: "Narration voice",
            .spanishSpain: "Voz de la narración"
        ],
        .settingsVoiceAuto: [
            .portugueseBrazil: "Automática (melhor no aparelho)",
            .englishUS: "Automatic (best on-device)",
            .spanishSpain: "Automática (mejor en el dispositivo)"
        ],
        .settingsVoiceHint: [
            .portugueseBrazil: "Só vozes do sistema no iPhone — 100% offline. Prefira Premium ou Aprimorada.",
            .englishUS: "System voices on this iPhone only — 100% offline. Prefer Premium or Enhanced.",
            .spanishSpain: "Solo voces del sistema en el iPhone — 100% offline. Prefiere Premium o Mejorada."
        ],
        .settingsVoicePremiumTip: [
            .portugueseBrazil: "Para uma voz mais natural: Ajustes do iPhone → Acessibilidade → Conteúdo falado → Vozes. Baixe Premium/Aprimorada (pt/en/es). O download fica no aparelho; a narração não usa nuvem.",
            .englishUS: "For a more natural voice: iPhone Settings → Accessibility → Spoken Content → Voices. Download Premium/Enhanced (pt/en/es). Files stay on-device; narration never uses the cloud.",
            .spanishSpain: "Para una voz más natural: Ajustes del iPhone → Accesibilidad → Contenido hablado → Voces. Descarga Premium/Mejorada (pt/en/es). Los archivos quedan en el dispositivo; la narración no usa la nube."
        ],
        .settingsStorage: [
            .portugueseBrazil: "Armazenamento",
            .englishUS: "Storage",
            .spanishSpain: "Almacenamiento"
        ],
        .settingsStoriesSize: [
            .portugueseBrazil: "Histórias e imagens",
            .englishUS: "Stories and images",
            .spanishSpain: "Historias e imágenes"
        ],
        .settingsRefreshSize: [
            .portugueseBrazil: "Atualizar tamanho",
            .englishUS: "Refresh size",
            .spanishSpain: "Actualizar tamaño"
        ],
        .settingsPrivacy: [
            .portugueseBrazil: "Privacidade",
            .englishUS: "Privacy",
            .spanishSpain: "Privacidad"
        ],
        .settingsPrivacyBody: [
            .portugueseBrazil: "Fotos, personagens, contos e narração ficam no aparelho. Geração e TTS são offline (packs opcionais só baixam arquivos; sem processamento na nuvem). Não há conta nem rede social.",
            .englishUS: "Photos, characters, stories, and narration stay on this device. Generation and TTS are offline (optional packs only download files; no cloud processing). No account, no social network.",
            .spanishSpain: "Fotos, personajes, historias y narración se quedan en el dispositivo. Generación y TTS son offline (packs opcionales solo descargan archivos; sin procesado en la nube). Sin cuenta ni red social."
        ],
        .settingsParental: [
            .portugueseBrazil: "Conta parental",
            .englishUS: "Parental gate",
            .spanishSpain: "Control parental"
        ],
        .settingsResetAge: [
            .portugueseBrazil: "Repetir aviso de idade (18+)",
            .englishUS: "Show age notice again (18+)",
            .spanishSpain: "Mostrar aviso de edad otra vez (18+)"
        ],

        .language: [
            .portugueseBrazil: "Idioma",
            .englishUS: "Language",
            .spanishSpain: "Idioma"
        ],

        .settingsResources: [
            .portugueseBrazil: "Recursos neste iPhone",
            .englishUS: "Features on this iPhone",
            .spanishSpain: "Funciones en este iPhone"
        ],
        .settingsResourcesHint: [
            .portugueseBrazil: "Cada recurso declara a versão mínima de iOS. Se não estiver disponível, mostramos o motivo.",
            .englishUS: "Each feature declares a minimum iOS version. If unavailable, we explain why.",
            .spanishSpain: "Cada función declara la versión mínima de iOS. Si no está disponible, explicamos el motivo."
        ],
        .settingsOSVersion: [
            .portugueseBrazil: "Versão do iOS",
            .englishUS: "iOS version",
            .spanishSpain: "Versión de iOS"
        ],

        .featureBannerGraphicsOff: [
            .portugueseBrazil: "Pipeline de ilustração desligado neste build.",
            .englishUS: "Illustration pipeline is disabled in this build.",
            .spanishSpain: "El pipeline de ilustración está desactivado en este build."
        ],
        .featureBannerFoundationModelsOff: [
            .portugueseBrazil: "Foundation Models (IA da Apple) não está disponível neste iOS/hardware. As histórias só são geradas por LLM no aparelho (iOS 26+ com Apple Intelligence, ou pack local). Não usamos textos pré-prontos.",
            .englishUS: "Apple Foundation Models are not available on this iOS/hardware. Stories are LLM-generated only (iOS 26+ with Apple Intelligence, or a local pack). Pre-written templates are not used.",
            .spanishSpain: "Foundation Models de Apple no está disponible en este iOS/hardware. Las historias solo se generan con LLM en el dispositivo (iOS 26+ con Apple Intelligence o pack local). No usamos textos preescritos."
        ]
    ]
}

extension L10n {
    static func format(_ key: Key, _ lang: AppLanguage, _ args: CVarArg...) -> String {
        let format = t(key, lang)
        return String(format: format, locale: lang.locale, arguments: args)
    }
}

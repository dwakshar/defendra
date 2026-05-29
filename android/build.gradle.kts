allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force consistent JVM 17 across all subprojects.
// Kotlin: subprojects configureEach is fine — Kotlin plugin registers tasks early.
// Java: evaluationDependsOn(":app") above causes all subprojects to be evaluated
//       before this file finishes, making afterEvaluate illegal here. Use
//       gradle.projectsEvaluated instead — it fires once after every project is done,
//       guaranteeing we override tflite_flutter's hard-coded Java 11 compileOptions.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

gradle.projectsEvaluated {
    subprojects {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

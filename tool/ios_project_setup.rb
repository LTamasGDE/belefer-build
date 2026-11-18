# Az iOS-projekt kiegészítése (macOS-en, az xcodeproj gemmel):
#  - App Group jogosultság a Runnernek,
#  - a szövegfelismerés (ML Kit) erőforráscsomagja a Runner erőforrásai közé,
#  - a kezdőképernyő-widget (WidgetKit) bővítmény célja és beágyazása.
# Többször is futtatható: ami már megvan, azt nem adja hozzá újra.
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, 'ios', 'Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Nincs Runner cél')

def group_for(project, name)
  group = project.main_group.children.find { |c| c.display_name == name && c.isa == 'PBXGroup' }
  group ||= project.main_group.new_group(name, name)
  group
end

# 1. Jogosultságok a Runnernek.
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
runner_group = project.main_group.children.find { |c| c.display_name == 'Runner' }
if runner_group && runner_group.files.none? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

# 2. ML Kit erőforráscsomag.
bundles = group_for(project, 'mlkit_bundles')
unless runner.resources_build_phase.files_references.compact.any? { |f| f.path.to_s.end_with?('LatinOCRResources.bundle') }
  ref = bundles.new_reference('LatinOCRResources.bundle')
  ref.last_known_file_type = 'wrapper.plug-in'
  runner.resources_build_phase.add_file_reference(ref, true)
  puts 'ML Kit erőforráscsomag hozzáadva.'
end

# 3. Widget-bővítmény.
widget = project.targets.find { |t| t.name == 'BeleferWidget' }
unless widget
  widget = project.new_target(:app_extension, 'BeleferWidget', :ios, '15.0')
  widget_group = group_for(project, 'BeleferWidget')
  swift = widget_group.new_reference('BeleferWidget.swift')
  widget_group.new_reference('Info.plist')
  widget_group.new_reference('BeleferWidget.entitlements')
  widget.add_file_references([swift])
  widget.add_system_framework(%w[WidgetKit SwiftUI])

  # A Runner minden konfigurációjához (Debug, Release, Profile) legyen
  # azonos nevű konfiguráció, ugyanazzal a Flutter xcconfiggal (ebből jön a
  # verziószám).
  runner.build_configurations.each do |runner_config|
    config = widget.build_configurations.find { |c| c.name == runner_config.name }
    config ||= widget.add_build_configuration(
      runner_config.name, runner_config.name == 'Debug' ? :debug : :release
    )
    config.base_configuration_reference = runner_config.base_configuration_reference
    settings = config.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.ventyh1.belefer.widget'
    settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    settings['INFOPLIST_FILE'] = 'BeleferWidget/Info.plist'
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['CODE_SIGN_ENTITLEMENTS'] = 'BeleferWidget/BeleferWidget.entitlements'
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['SWIFT_VERSION'] = '5.0'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    settings['SKIP_INSTALL'] = 'YES'
    settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    settings['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'
    ]
    %w[DEVELOPMENT_TEAM].each do |key|
      value = runner_config.build_settings[key]
      settings[key] = value if value
    end
  end

  runner.add_dependency(widget)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  build_file = embed.add_file_reference(widget.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts 'Widget-bővítmény hozzáadva.'
end

# A beágyazás a „Thin Binary” lépés előtt fusson (különben körkörös függőség).
phases = runner.build_phases
embed = phases.find { |p| p.respond_to?(:name) && p.name == 'Embed Foundation Extensions' }
thin = phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if embed && thin && phases.index(embed) > phases.index(thin)
  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
  puts 'Beágyazási lépés a Thin Binary elé helyezve.'
end

project.save
puts 'iOS-projekt kész.'

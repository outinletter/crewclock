require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
FileUtils.rm_rf('CrewClockNative.xcodeproj')
proj = Xcodeproj::Project.new('CrewClockNative.xcodeproj')
team = 'A7QB8PT33N'
shared = proj.main_group.new_file('Shared/CrewSurfaceModels.swift')

app = proj.new_target(:application, 'CrewClockNative', :ios, '26.0')
group = proj.main_group.new_group('CrewClockNative', 'CrewClockNative')
refs = Dir.glob('CrewClockNative/*.swift').sort.map { |f| group.new_file(File.basename(f)) }
app.add_file_references(refs + [shared])
app.add_resources([group.new_file('Assets.xcassets'), group.new_file('Resources/airport_timezones.json'), group.new_file('PrivacyInfo.xcprivacy')])
group.new_file('Info.plist'); group.new_file('CrewClock.entitlements')
app.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.addvalue.crewclock'
  s['PRODUCT_NAME'] = 'CrewClock'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['INFOPLIST_FILE'] = 'CrewClockNative/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'CrewClockNative/CrewClock.entitlements'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'CrewClock'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  s['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['DEVELOPMENT_TEAM'] = team
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['MARKETING_VERSION'] = '1.0.6'
  s['CURRENT_PROJECT_VERSION'] = '101'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
  s['SWIFT_VERSION'] = '5.0'
end

widget = proj.new_target(:app_extension, 'CrewClockWidgets', :ios, '26.0')
wgroup = proj.main_group.new_group('CrewClockWidgets', 'CrewClockWidgets')
widget.add_file_references([wgroup.new_file('CrewClockWidgets.swift'), shared])
widget.add_resources([wgroup.new_file('Assets.xcassets'), wgroup.new_file('PrivacyInfo.xcprivacy')])
widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.addvalue.crewclock.widgets'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['INFOPLIST_FILE'] = 'CrewClockWidgets/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'CrewClockWidgets/CrewClockWidgets.entitlements'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['DEVELOPMENT_TEAM'] = team
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['MARKETING_VERSION'] = '1.0.6'
  s['CURRENT_PROJECT_VERSION'] = '101'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
  s['SWIFT_VERSION'] = '5.0'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
proj.build_configurations.each { |c| c.build_settings['SWIFT_VERSION'] = '5.0' }
proj.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as('CrewClockNative.xcodeproj', 'CrewClockNative', true)
puts 'generated'

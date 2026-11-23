/// Supported animation states for all interactive MamPet monsters.
enum MonsterAnimation {
  idle('idle', 'Idle', 'Napas santai & berkedip alami'),
  happy('happy', 'Happy', 'Lompat ceria & tersenyum senang'),
  pet('pet', 'Pet', 'Menyipit manja saat dielus'),
  eat('eat', 'Eat', 'Mengunyah energi makanan'),
  sleep('sleep', 'Sleep', 'Tidur nyenyak sambil bernapas pelan'),
  play('play', 'Play', 'Gerakan khas spesies penuh semangat'),
  special('special', 'Special', 'Aksi spesial khas spesies monster'),
  evolve('evolve', 'Evolve', 'Bersinar & siap berevolusi');

  const MonsterAnimation(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

  /// Whether this state should persist continuously rather than auto-returning to [idle].
  bool get isPersistentLoop => this == MonsterAnimation.idle || this == MonsterAnimation.sleep;

  /// Canonical OpenBone 0.4.8 state machine trigger name for this state.
  String get openBoneTrigger => switch (this) {
        MonsterAnimation.idle => 'wake',
        MonsterAnimation.happy => 'happy',
        MonsterAnimation.pet => 'pet',
        MonsterAnimation.eat => 'eat',
        MonsterAnimation.sleep => 'sleep',
        MonsterAnimation.play => 'play',
        MonsterAnimation.special => 'special',
        MonsterAnimation.evolve => 'special',
      };

  static MonsterAnimation fromCode(String? code) {
    for (final state in MonsterAnimation.values) {
      if (state.code == code) return state;
    }
    return MonsterAnimation.idle;
  }

  /// Maps an OpenBone state name (`idle`, `happy`, `pet`, `eat`, `sleep`, `play`, `special`)
  /// back to [MonsterAnimation].
  static MonsterAnimation fromOpenBoneState(String? name) {
    return switch (name) {
      'idle' => MonsterAnimation.idle,
      'happy' => MonsterAnimation.happy,
      'pet' => MonsterAnimation.pet,
      'eat' => MonsterAnimation.eat,
      'sleep' => MonsterAnimation.sleep,
      'play' => MonsterAnimation.play,
      'special' => MonsterAnimation.special,
      _ => MonsterAnimation.idle,
    };
  }
}
